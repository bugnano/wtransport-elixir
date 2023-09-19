use rustler::{
    Atom, Binary, Encoder, Env, LocalPid, NifStruct, OwnedBinary, OwnedEnv, ResourceArc, Term,
};
use std::collections::HashMap;
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
use wtransport::stream::{RecvStream, SendStream};
use wtransport::tls::Certificate;
use wtransport::Connection;
use wtransport::Endpoint;
use wtransport::ServerConfig;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        session_request,
        connection_request,
        datagram_received,
        conn_closed,
        stream_request,
        bi,
        uni,
        data_received,
        stream_closed,
        pid_crashed,
        remote_address,
        max_datagram_size,
        rtt,
    }
}

struct XShutdownSender(tokio::sync::broadcast::Sender<()>);
struct XRequestSender(tokio::sync::mpsc::Sender<(Atom, LocalPid)>);
struct XDataSender(tokio::sync::mpsc::Sender<OwnedBinary>);

#[derive(NifStruct)]
#[module = "Wtransport.Runtime"]
struct NifRuntime {
    shutdown_tx: ResourceArc<XShutdownSender>,
}

#[derive(NifStruct)]
#[module = "Wtransport.SessionRequest"]
struct NifSessionRequest {
    authority: String,
    path: String,
    origin: Option<String>,
    user_agent: Option<String>,
    headers: HashMap<String, String>,
    request_tx: ResourceArc<XRequestSender>,
}

#[derive(NifStruct)]
#[module = "Wtransport.ConnectionRequest"]
struct NifConnectionRequest {
    stable_id: usize,
    send_dgram_tx: ResourceArc<XDataSender>,
}

#[derive(NifStruct)]
#[module = "Wtransport.StreamRequest"]
struct NifStreamRequest {
    stream_type: Atom,
    request_tx: ResourceArc<XRequestSender>,
    write_all_tx: Option<ResourceArc<XDataSender>>,
}

fn load(env: Env, _term: Term) -> bool {
    init_logging();

    debug!("load(term: {:?})", _term);

    rustler::resource!(XShutdownSender, env);
    rustler::resource!(XRequestSender, env);
    rustler::resource!(XDataSender, env);

    true
}

fn init_logging() {
    let env_filter = EnvFilter::builder()
        .with_default_directive(LevelFilter::OFF.into())
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

    let mut addrs_iter = (host, port).to_socket_addrs()?;

    let Some(bind_address) = addrs_iter.next() else {
        return Err("bind_address is empty".into());
    };

    let certificate = Certificate::load(certfile, keyfile)?;

    let config = ServerConfig::builder()
        .with_bind_address(bind_address, false)
        .with_certificate(certificate)
        .keep_alive_interval(Some(Duration::from_secs(3)))
        .build();

    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()?;

    let shutdown_tx2 = shutdown_tx.clone();
    std::thread::spawn(move || {
        runtime.block_on(async {
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
                debug!("Connection accepted");
                tokio::spawn(
                    handle_connection(pid, shutdown_tx.clone(), incoming_session)
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
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    incoming_session: IncomingSession,
) {
    info!("Waiting for session request...");

    let session_request = match incoming_session.await {
        Ok(request) => request,
        Err(error) => {
            error!("{:?}", error);
            return;
        }
    };

    let authority = session_request.authority().to_string();
    let path = session_request.path().to_string();
    let origin = session_request.origin().map(|origin| origin.to_string());
    let user_agent = session_request
        .user_agent()
        .map(|user_agent| user_agent.to_string());

    let headers = session_request.headers().clone();

    info!("New session: Authority: '{}', Path: '{}'", authority, path);

    let (request_tx, mut request_rx) = tokio::sync::mpsc::channel(1);

    let mut msg_env = OwnedEnv::new();
    msg_env.send_and_clear(&runtime_pid, |env| {
        (
            atoms::session_request(),
            NifSessionRequest {
                authority,
                path,
                origin,
                user_agent,
                headers,
                request_tx: ResourceArc::new(XRequestSender(request_tx)),
            },
        )
            .encode(env)
    });

    let (result, pid) = request_rx.recv().await.unwrap();

    match handle_connection_impl(shutdown_tx, session_request, request_rx, result, pid).await {
        Ok(()) => (),
        Err(error) => {
            msg_env.send_and_clear(&pid, |env| (atoms::error(), error.to_string()).encode(env));
            error!("{:?}", error);
        }
    }
}

async fn handle_connection_impl(
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    session_request: SessionRequest,
    mut request_rx: tokio::sync::mpsc::Receiver<(Atom, LocalPid)>,
    result: Atom,
    pid: LocalPid,
) -> Result<(), Box<dyn Error>> {
    let mut msg_env = OwnedEnv::new();
    let mut shutdown_rx = shutdown_tx.subscribe();
    let mut id = 0;

    if result != atoms::ok() {
        info!("Session request refused");
        session_request.not_found().await;
        return Ok(());
    }

    debug!("Waiting for connection request...");

    let connection = session_request.accept().await?;

    let (send_dgram_tx, mut send_dgram_rx) = tokio::sync::mpsc::channel(1);

    msg_env.send_and_clear(&pid, |env| {
        (
            atoms::connection_request(),
            NifConnectionRequest {
                stable_id: connection.stable_id(),
                send_dgram_tx: ResourceArc::new(XDataSender(send_dgram_tx)),
            },
        )
            .encode(env)
    });

    loop {
        if let Some(result) = handle_request(&connection, request_rx.recv().await.unwrap()) {
            if !result {
                info!("Connection refused");
                return Ok(());
            }
            break;
        }
    }

    info!("Waiting for data from client...");

    loop {
        tokio::select! {
            stream = connection.accept_bi() => {
                let (send_stream, recv_stream) = stream?;
                info!("Accepted BI stream");

                tokio::spawn(
                    handle_stream(
                        pid,
                        shutdown_tx.clone(),
                        Some(send_stream),
                        recv_stream,
                    )
                    .instrument(info_span!("Stream (bi)", id)),
                );
                id += 1;
            }
            stream = connection.accept_uni() => {
                let stream = stream?;
                info!("Accepted UNI stream");

                tokio::spawn(
                    handle_stream(
                        pid,
                        shutdown_tx.clone(),
                        None,
                        stream,
                    )
                    .instrument(info_span!("Stream (uni)", id)),
                );
                id += 1;
            }
            dgram = connection.receive_datagram() => {
                let dgram = dgram?;
                let str_data = unsafe { std::str::from_utf8_unchecked(&dgram) };

                msg_env.send_and_clear(&pid, |env| {
                    (
                        atoms::datagram_received(),
                        str_data,
                    )
                        .encode(env)
                });

                trace!("Received (dgram) '{str_data}' from client");
            }
            _ = connection.closed() => {
                msg_env.send_and_clear(&pid, |env| atoms::conn_closed().encode(env));

                debug!("Connection closed");

                return Ok(());
            }
            Some(dgram) = send_dgram_rx.recv() => {
                connection.send_datagram(dgram.as_slice())?;
            }
            Some(request) = request_rx.recv() => {
                if let Some(false) = handle_request(&connection, request) {
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

fn handle_request(connection: &Connection, (request, pid): (Atom, LocalPid)) -> Option<bool> {
    let mut msg_env = OwnedEnv::new();

    if request == atoms::ok() {
        return Some(true);
    } else if request == atoms::error() {
        return Some(false);
    } else if request == atoms::pid_crashed() {
        info!("Handled pid crashed");

        return Some(false);
    } else if request == atoms::remote_address() {
        let remote_address = connection.remote_address();

        msg_env.send_and_clear(&pid, |env| {
            (
                atoms::remote_address(),
                remote_address.ip().to_string(),
                remote_address.port(),
            )
                .encode(env)
        });
    } else if request == atoms::max_datagram_size() {
        let max_datagram_size = connection.max_datagram_size();

        msg_env.send_and_clear(&pid, |env| {
            (atoms::max_datagram_size(), max_datagram_size).encode(env)
        });
    } else if request == atoms::rtt() {
        let rtt = connection.rtt();

        msg_env.send_and_clear(&pid, |env| (atoms::rtt(), rtt.as_secs_f64()).encode(env));
    }

    None
}

async fn handle_stream(
    socket_pid: LocalPid,
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    send_stream: Option<SendStream>,
    recv_stream: RecvStream,
) {
    let (request_tx, mut request_rx) = tokio::sync::mpsc::channel(1);
    let (write_all_tx, write_all_rx) = tokio::sync::mpsc::channel(1);

    let mut msg_env = OwnedEnv::new();
    msg_env.send_and_clear(&socket_pid, |env| {
        (
            atoms::stream_request(),
            match send_stream {
                Some(_) => NifStreamRequest {
                    stream_type: atoms::bi(),
                    request_tx: ResourceArc::new(XRequestSender(request_tx)),
                    write_all_tx: Some(ResourceArc::new(XDataSender(write_all_tx))),
                },
                None => NifStreamRequest {
                    stream_type: atoms::uni(),
                    request_tx: ResourceArc::new(XRequestSender(request_tx)),
                    write_all_tx: None,
                },
            },
        )
            .encode(env)
    });

    let (result, pid) = request_rx.recv().await.unwrap();

    match handle_stream_impl(
        shutdown_tx,
        send_stream,
        recv_stream,
        request_rx,
        write_all_rx,
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

async fn handle_stream_impl(
    shutdown_tx: tokio::sync::broadcast::Sender<()>,
    mut send_stream: Option<SendStream>,
    mut recv_stream: RecvStream,
    mut request_rx: tokio::sync::mpsc::Receiver<(Atom, LocalPid)>,
    mut write_all_rx: tokio::sync::mpsc::Receiver<OwnedBinary>,
    result: Atom,
    pid: LocalPid,
) -> Result<(), Box<dyn Error>> {
    let mut buffer = vec![0; 65536].into_boxed_slice();
    let mut msg_env = OwnedEnv::new();
    let mut shutdown_rx = shutdown_tx.subscribe();
    let mut recv_stream_open = true;

    if result != atoms::ok() {
        info!("Stream refused");
        return Ok(());
    }

    loop {
        tokio::select! {
            bytes_read = recv_stream.read(&mut buffer), if recv_stream_open => {
                if let Some(bytes_read) = bytes_read? {
                    let str_data = unsafe { std::str::from_utf8_unchecked(&buffer[..bytes_read]) };

                    msg_env.send_and_clear(&pid, |env| {
                        (
                            atoms::data_received(),
                            str_data,
                        )
                            .encode(env)
                    });

                    trace!("Received '{str_data}' from client");
                } else {
                    recv_stream_open = false;

                    msg_env.send_and_clear(&pid, |env| atoms::stream_closed().encode(env));

                    debug!("Receiving end of stream closed");
                }
            }
            Some(data) = write_all_rx.recv() => {
                if let Some(stream) = send_stream.as_mut() {
                    stream.write_all(data.as_slice()).await?;
                }
            }
            Some((request, _request_pid)) = request_rx.recv() => {
                if request == atoms::pid_crashed() {
                    info!("Handled pid crashed");
                    return Ok(());
                }
            }
            _ = shutdown_rx.recv() => {
                info!("Stream loop stopped");
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
fn reply_request(
    tx_channel: ResourceArc<XRequestSender>,
    result: Atom,
    pid: LocalPid,
) -> Result<(), String> {
    debug!("reply_request()");

    let now = std::time::Instant::now();

    match tx_channel.0.blocking_send((result, pid)) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            debug!("elapsed_time (reply_request): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn send_data(tx_channel: ResourceArc<XDataSender>, data: Binary) -> Result<(), String> {
    trace!("send_data()");

    let now = std::time::Instant::now();

    match tx_channel.0.blocking_send(data.to_owned().unwrap()) {
        Ok(_) => {
            let elapsed_time = now.elapsed();
            trace!("elapsed_time (send_data): {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

rustler::init!(
    "Elixir.Wtransport.Native",
    [start_runtime, stop_runtime, reply_request, send_data],
    load = load
);
