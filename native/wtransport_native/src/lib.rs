use rustler::{Atom, Encoder, Env, LocalPid, NifStruct, OwnedEnv, ResourceArc, Term};
use std::error::Error;
use std::net::ToSocketAddrs;
use std::time::Duration;
use tracing::debug;
use tracing::error;
use tracing::info;
use tracing::info_span;
use tracing::Instrument;
use wtransport::endpoint::IncomingSession;
use wtransport::tls::Certificate;
use wtransport::Endpoint;
use wtransport::ServerConfig;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        session_request,
    }
}

struct XRuntime(tokio::runtime::Runtime);
struct XShutdownSender(tokio::sync::broadcast::Sender<()>);
struct XSessionRequestSender(tokio::sync::mpsc::Sender<(Atom, LocalPid)>);

#[derive(NifStruct)]
#[module = "Wtransport.NifRuntime"]
struct NifRuntime {
    rt: ResourceArc<XRuntime>,
    shutdown_tx: ResourceArc<XShutdownSender>,
}

#[derive(NifStruct)]
#[module = "Wtransport.SessionRequest"]
struct SessionRequest {
    authority: String,
    path: String,
    channel: ResourceArc<XSessionRequestSender>,
}

fn load(env: Env, _term: Term) -> bool {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    debug!("[FRI] -- load -- term: {:?}", _term);
    rustler::resource!(XRuntime, env);
    rustler::resource!(XShutdownSender, env);
    rustler::resource!(XSessionRequestSender, env);

    true
}

#[rustler::nif(schedule = "DirtyCpu")]
fn start_runtime(
    pid: LocalPid,
    host: &str,
    port: u16,
    cert_chain: &str,
    priv_key: &str,
) -> Result<NifRuntime, String> {
    debug!("[FRI] -- start_runtime -- pid: {:?}", pid.as_c_arg());
    debug!("[FRI] -- start_runtime -- host: {:?}", host);
    debug!("[FRI] -- start_runtime -- port: {:?}", port);
    debug!("[FRI] -- start_runtime -- cert_chain: {:?}", cert_chain);
    debug!("[FRI] -- start_runtime -- priv_key: {:?}", priv_key);

    let now = std::time::Instant::now();

    match start_runtime_impl(pid, host, port, cert_chain, priv_key) {
        Ok(runtime) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time: {:?}", elapsed_time);

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
    cert_chain: &str,
    priv_key: &str,
) -> Result<NifRuntime, Box<dyn Error>> {
    let (tx, rx) = std::sync::mpsc::channel();
    let (shutdown_tx, shutdown_rx) = tokio::sync::broadcast::channel(1);

    let mut addrs_iter = (host, port).to_socket_addrs()?;

    let Some(bind_address) = addrs_iter.next() else {
        return Err("bind_address is empty".into());
    };

    let certificate = Certificate::load(cert_chain, priv_key)?;

    let config = ServerConfig::builder()
        .with_bind_address(bind_address)
        .with_certificate(certificate)
        .keep_alive_interval(Some(Duration::from_secs(3)))
        .build();

    let runtime = ResourceArc::new(XRuntime(
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()?,
    ));
    let rt = ResourceArc::clone(&runtime);

    let shutdown_tx2 = shutdown_tx.clone();
    std::thread::spawn(move || {
        runtime.0.block_on(async {
            match server_loop(pid, config, tx.clone(), shutdown_tx2, shutdown_rx).await {
                Ok(()) => (),
                Err(error) => {
                    let _ = tx.send(Err(error.to_string()));
                }
            };
        });
    });

    rx.recv()??;

    Ok(NifRuntime {
        rt: rt,
        shutdown_tx: ResourceArc::new(XShutdownSender(shutdown_tx)),
    })
}

async fn server_loop(
    pid: LocalPid,
    config: ServerConfig,
    tx: std::sync::mpsc::Sender<Result<(), String>>,
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    mut shutdown_rx: tokio::sync::broadcast::Receiver<()>,
) -> Result<(), Box<dyn Error>> {
    let server = Endpoint::server(config)?;

    info!("Server started");

    tx.send(Ok(()))?;

    tokio::select! {
        _ = async {
            for id in 0.. {
                let incoming_session = server.accept().await;
                debug!("[FRI] -- Connection received");
                tokio::spawn(
                    handle_connection(pid, shutdown_tx.subscribe(), incoming_session)
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
    pid: LocalPid,
    shutdown_rx: tokio::sync::broadcast::Receiver<()>,
    incoming_session: IncomingSession,
) {
    match handle_connection_impl(pid, shutdown_rx, incoming_session).await {
        Ok(()) => (),
        Err(error) => {
            error!("{:?}", error);
        }
    }
}

async fn handle_connection_impl(
    runtime_pid: LocalPid,
    mut shutdown_rx: tokio::sync::broadcast::Receiver<()>,
    incoming_session: IncomingSession,
) -> Result<(), Box<dyn Error>> {
    let mut buffer = vec![0; 65536].into_boxed_slice();

    info!("Waiting for session request...");

    let session_request = incoming_session.await?;
    let authority = session_request.authority().to_string();
    let path = session_request.path().to_string();

    info!("New session: Authority: '{}', Path: '{}'", authority, path);

    let (session_request_tx, mut session_request_rx) = tokio::sync::mpsc::channel(1);

    let mut msg_env = OwnedEnv::new();
    msg_env.send_and_clear(&runtime_pid, |env| {
        (
            atoms::session_request(),
            SessionRequest {
                authority: authority,
                path: path,
                channel: ResourceArc::new(XSessionRequestSender(session_request_tx)),
            },
        )
            .encode(env)
    });

    let Some((result, pid)) = session_request_rx.recv().await else {
        return Err("session_request_tx channel closed".into());
    };

    if result != atoms::ok() {
        info!("Session request refused");
        session_request.not_found().await;
        return Ok(());
    }

    let connection = session_request.accept().await?;

    info!("Waiting for data from client...");

    loop {
        tokio::select! {
            // TODO: session_request_rx can receive new data if the supervisor restarts the process
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

                info!("Received (dgram) '{str_data}' from client");

                connection.send_datagram(b"ACK")?;
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
    debug!("[FRI] -- call to stop_runtime()");

    let now = std::time::Instant::now();

    match runtime.shutdown_tx.0.send(()) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time: {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn reply_session_request(
    request: SessionRequest,
    result: Atom,
    pid: LocalPid,
) -> Result<(), String> {
    debug!("[FRI] -- call to reply_session_request()");

    let now = std::time::Instant::now();

    match request.channel.0.blocking_send((result, pid)) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time: {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

rustler::init!(
    "Elixir.Wtransport.Native",
    [start_runtime, stop_runtime, reply_session_request,],
    load = load
);
