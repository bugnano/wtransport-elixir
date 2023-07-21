use rustler::{Atom, Encoder, Env, LocalPid, NifStruct, OwnedEnv, ResourceArc, Term};
use std::error::Error;
use std::net::ToSocketAddrs;
use std::time::Duration;
use tracing::debug;
use tracing::error;
use tracing::info;
use tracing::info_span;
use tracing::trace;
use tracing::Instrument;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::EnvFilter;
use wtransport::endpoint::{IncomingSession, SessionRequest};
use wtransport::tls::Certificate;
use wtransport::Endpoint;
use wtransport::ServerConfig;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        session_request,
        datagram_received,
    }
}

struct XShutdownSender(tokio::sync::broadcast::Sender<()>);
struct XCrashSender(tokio::sync::broadcast::Sender<LocalPid>);
struct XSessionRequestSender(tokio::sync::mpsc::Sender<(Atom, LocalPid)>);
struct XDatagramSender(tokio::sync::mpsc::Sender<String>);

#[derive(NifStruct)]
#[module = "Wtransport.Runtime"]
struct NifRuntime {
    shutdown_tx: ResourceArc<XShutdownSender>,
    pid_crashed_tx: ResourceArc<XCrashSender>,
}

#[derive(NifStruct)]
#[module = "Wtransport.Socket"]
struct Socket {
    authority: String,
    path: String,
    session_request_tx: ResourceArc<XSessionRequestSender>,
    send_dgram_tx: ResourceArc<XDatagramSender>,
}

fn load(env: Env, _term: Term) -> bool {
    init_logging();

    debug!("load(term: {:?})", _term);

    rustler::resource!(XShutdownSender, env);
    rustler::resource!(XCrashSender, env);
    rustler::resource!(XSessionRequestSender, env);
    rustler::resource!(XDatagramSender, env);

    true
}

fn init_logging() {
    let env_filter = EnvFilter::builder()
        .with_default_directive(LevelFilter::DEBUG.into())
        .from_env_lossy();

    tracing_subscriber::fmt()
        .with_target(true)
        .with_level(true)
        .with_env_filter(env_filter)
        .init();
}

#[rustler::nif(schedule = "DirtyCpu")]
fn start_runtime(
    pid: LocalPid,
    host: &str,
    port: u16,
    certfile: &str,
    keyfile: &str,
) -> Result<NifRuntime, String> {
    debug!(
        "start_runtime(pid: {:?}, host: {:?}, port: {:?}, certfile: {:?}, keyfile: {:?})",
        pid.as_c_arg(),
        host,
        port,
        certfile,
        keyfile
    );

    let now = std::time::Instant::now();

    match start_runtime_impl(pid, host, port, certfile, keyfile) {
        Ok(runtime) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time (start_runtime): {:?}", elapsed_time);

            Ok(runtime)
        }
        Err(error) => {
            error!("{:?}", error);
            Err(error.to_string())
        }
    }
}

fn start_runtime_impl(
    pid: LocalPid,
    host: &str,
    port: u16,
    certfile: &str,
    keyfile: &str,
) -> Result<NifRuntime, Box<dyn Error>> {
    let (tx, rx) = std::sync::mpsc::channel();
    let (shutdown_tx, shutdown_rx) = tokio::sync::broadcast::channel(1);
    let (pid_crashed_tx, _pid_crashed_rx) = tokio::sync::broadcast::channel(1);

    let mut addrs_iter = (host, port).to_socket_addrs()?;

    let Some(bind_address) = addrs_iter.next() else {
        return Err("bind_address is empty".into());
    };

    let certificate = Certificate::load(certfile, keyfile)?;

    let config = ServerConfig::builder()
        .with_bind_address(bind_address)
        .with_certificate(certificate)
        .keep_alive_interval(Some(Duration::from_secs(3)))
        .build();

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    let shutdown_tx2 = shutdown_tx.clone();
    let pid_crashed_tx2 = pid_crashed_tx.clone();
    std::thread::spawn(move || {
        runtime.block_on(async {
            match server_loop(
                pid,
                config,
                tx.clone(),
                shutdown_tx2,
                shutdown_rx,
                pid_crashed_tx2,
            )
            .await
            {
                Ok(()) => (),
                Err(error) => {
                    let _ = tx.send(Err(error.to_string()));
                }
            };
        });
    });

    rx.recv()??;

    Ok(NifRuntime {
        shutdown_tx: ResourceArc::new(XShutdownSender(shutdown_tx)),
        pid_crashed_tx: ResourceArc::new(XCrashSender(pid_crashed_tx)),
    })
}

async fn server_loop(
    pid: LocalPid,
    config: ServerConfig,
    tx: std::sync::mpsc::Sender<Result<(), String>>,
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    mut shutdown_rx: tokio::sync::broadcast::Receiver<()>,
    pid_crashed_tx: tokio::sync::broadcast::Sender<LocalPid>,
) -> Result<(), Box<dyn Error>> {
    let server = Endpoint::server(config)?;

    info!("Server started");

    tx.send(Ok(()))?;

    tokio::select! {
        _ = async {
            for id in 0.. {
                let incoming_session = server.accept().await;
                debug!("Connection accepted");
                tokio::spawn(
                    handle_connection(pid, shutdown_tx.subscribe(), pid_crashed_tx.clone(), incoming_session)
                        .instrument(info_span!("Connection", id)),
                );
            }
        } => {}
        _ = shutdown_rx.recv() => {
            info!("Server stopped");
        }
    }

    Ok(())
}

async fn handle_connection(
    runtime_pid: LocalPid,
    shutdown_rx: tokio::sync::broadcast::Receiver<()>,
    pid_crashed_tx: tokio::sync::broadcast::Sender<LocalPid>,
    incoming_session: IncomingSession,
) {
    let session_request = match incoming_session.await {
        Ok(request) => request,
        Err(error) => {
            error!("{:?}", error);
            return;
        }
    };

    // TODO: Expose all the fields, not only authority and path
    let authority = session_request.authority().to_string();
    let path = session_request.path().to_string();

    info!("New session: Authority: '{}', Path: '{}'", authority, path);

    let (session_request_tx, mut session_request_rx) = tokio::sync::mpsc::channel(1);
    let (send_dgram_tx, send_dgram_rx) = tokio::sync::mpsc::channel(1);

    let mut msg_env = OwnedEnv::new();
    msg_env.send_and_clear(&runtime_pid, |env| {
        (
            atoms::session_request(),
            Socket {
                authority: authority,
                path: path,
                session_request_tx: ResourceArc::new(XSessionRequestSender(session_request_tx)),
                send_dgram_tx: ResourceArc::new(XDatagramSender(send_dgram_tx)),
            },
        )
            .encode(env)
    });

    let (result, pid) = session_request_rx.recv().await.unwrap();

    match handle_connection_impl(
        shutdown_rx,
        pid_crashed_tx,
        session_request,
        send_dgram_rx,
        result,
        pid,
    )
    .await
    {
        Ok(()) => (),
        Err(error) => {
            msg_env.send_and_clear(&pid, |env| (atoms::error(), error.to_string()).encode(env));
            error!("{:?}", error);
        }
    }
}

async fn handle_connection_impl(
    mut shutdown_rx: tokio::sync::broadcast::Receiver<()>,
    pid_crashed_tx: tokio::sync::broadcast::Sender<LocalPid>,
    session_request: SessionRequest,
    mut send_dgram_rx: tokio::sync::mpsc::Receiver<String>,
    result: Atom,
    pid: LocalPid,
) -> Result<(), Box<dyn Error>> {
    let mut buffer = vec![0; 65536].into_boxed_slice();
    let mut msg_env = OwnedEnv::new();
    let mut pid_crashed_rx = pid_crashed_tx.subscribe();

    // This is for the ugly hack for comparing 2 pids
    let pid_repr = format!("{:?}", pid.as_c_arg());

    info!("Waiting for session request...");

    if result != atoms::ok() {
        info!("Session request refused");
        session_request.not_found().await;
        return Ok(());
    }

    let connection = session_request.accept().await?;

    info!("Waiting for data from client...");

    loop {
        tokio::select! {
            stream = connection.accept_bi() => {
                let mut stream = stream?;
                info!("Accepted BI stream");

                let bytes_read = match stream.1.read(&mut buffer).await? {
                    Some(bytes_read) => bytes_read,
                    None => continue,
                };

                let str_data = std::str::from_utf8(&buffer[..bytes_read])?;

                info!("Received (bi) '{str_data}' from client");

                stream.0.write_all(b"ACK").await?;
            }
            stream = connection.accept_uni() => {
                let mut stream = stream?;
                info!("Accepted UNI stream");

                let bytes_read = match stream.read(&mut buffer).await? {
                    Some(bytes_read) => bytes_read,
                    None => continue,
                };

                let str_data = std::str::from_utf8(&buffer[..bytes_read])?;

                info!("Received (uni) '{str_data}' from client");

                let mut stream = connection.open_uni().await?.await?;
                stream.write_all(b"ACK").await?;
            }
            dgram = connection.receive_datagram() => {
                let dgram = dgram?;
                let str_data = std::str::from_utf8(&dgram)?;

                msg_env.send_and_clear(&pid, |env| {
                    (
                        atoms::datagram_received(),
                        str_data,
                    )
                        .encode(env)
                });

                trace!("Received (dgram) '{str_data}' from client");
            }
            Some(dgram) = send_dgram_rx.recv() => {
                connection.send_datagram(dgram)?;
            }
            Ok(crashed_pid) = pid_crashed_rx.recv() => {
                // Ugly hack for comparing 2 pids:
                // The only way I found to compare 2 pids is to take advantage of the fact that
                // the ErlNifPid type has the Debug trait, so I compare the debug representation of the pids
                if format!("{:?}", crashed_pid.as_c_arg()) == pid_repr {
                    info!("Handled pid crashed");
                    return Ok(());
                }
            }
            _ = shutdown_rx.recv() => {
                info!("Connection loop stopped");
                return Ok(());
            }
        }
    }
}

#[rustler::nif]
fn stop_runtime(runtime: NifRuntime) -> Result<(), String> {
    debug!("stop_runtime()");

    let now = std::time::Instant::now();

    match runtime.shutdown_tx.0.send(()) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time (stop_runtime): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn pid_crashed(runtime: NifRuntime, pid: LocalPid) -> Result<(), String> {
    debug!("pid_crashed()");

    let now = std::time::Instant::now();

    match runtime.pid_crashed_tx.0.send(pid) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time (pid_crashed): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn reply_session_request(socket: Socket, result: Atom, pid: LocalPid) -> Result<(), String> {
    debug!("reply_session_request()");

    let now = std::time::Instant::now();

    match socket.session_request_tx.0.blocking_send((result, pid)) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time (reply_session_request): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn send_datagram(socket: Socket, dgram: String) -> Result<(), String> {
    trace!("send_datagram()");

    let now = std::time::Instant::now();

    match socket.send_dgram_tx.0.blocking_send(dgram) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            trace!("elapsed_time (send_datagram): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

rustler::init!(
    "Elixir.Wtransport.Native",
    [
        start_runtime,
        stop_runtime,
        pid_crashed,
        reply_session_request,
        send_datagram
    ],
    load = load
);
