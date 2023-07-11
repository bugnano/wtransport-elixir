use rustler::{Env, LocalPid, NifStruct, ResourceArc, Term};
use std::net::ToSocketAddrs;
use std::time::Duration;
use wtransport::tls::Certificate;
use wtransport::Endpoint;
use wtransport::ServerConfig;

struct XRuntime(tokio::runtime::Runtime);
struct XSender(tokio::sync::mpsc::Sender<()>);

#[derive(NifStruct)]
#[module = "Wtransport.NifRuntime"]
struct NifRuntime {
    rt: ResourceArc<XRuntime>,
    shutdown_tx: ResourceArc<XSender>,
}

fn load(env: Env, _term: Term) -> bool {
    println!("[FRI] -- load -- term: {:?}", _term);
    rustler::resource!(XRuntime, env);
    rustler::resource!(XSender, env);

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
    println!("[FRI] -- start_runtime -- pid: {:?}", pid.as_c_arg());
    println!("[FRI] -- start_runtime -- host: {:?}", host);
    println!("[FRI] -- start_runtime -- port: {:?}", port);
    println!("[FRI] -- start_runtime -- cert_chain: {:?}", cert_chain);
    println!("[FRI] -- start_runtime -- priv_key: {:?}", priv_key);

    let now = std::time::Instant::now();

    let (tx, rx) = std::sync::mpsc::channel();
    let (shutdown_tx, mut shutdown_rx) = tokio::sync::mpsc::channel(1);

    let mut addrs_iter = match (host, port).to_socket_addrs() {
        Ok(iter) => iter,
        Err(error) => return Err(error.to_string()),
    };

    let Some(bind_address) = addrs_iter.next() else {
        return Err("bind_address is empty".to_string());
    };

    let certificate = match Certificate::load(cert_chain, priv_key) {
        Ok(cert) => cert,
        Err(error) => return Err(error.to_string()),
    };

    let config = ServerConfig::builder()
        .with_bind_address(bind_address)
        .with_certificate(certificate)
        .keep_alive_interval(Some(Duration::from_secs(3)))
        .build();

    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build();

    match rt {
        Ok(runtime) => {
            let rt = ResourceArc::new(XRuntime(runtime));
            let runtime = ResourceArc::clone(&rt);

            std::thread::spawn(move || {
                runtime.0.block_on(async {
                    let server = match Endpoint::server(config) {
                        Ok(server) => server,
                        Err(error) => {
                            let _ = tx.send(Err(error));
                            return;
                        }
                    };

                    println!("Server ready!");

                    if let Ok(_) = tx.send(Ok(())) {
                        tokio::select! {
                            _ = async {
                                for id in 0.. {
                                    let incoming_session = server.accept().await;
                                    println!("[FRI] -- Connection received");
                                    //tokio::spawn(handle_connection(incoming_session).instrument(info_span!("Connection", id)));
                                }
                            } => {}
                            _ = shutdown_rx.recv() => {
                                println!("[FRI] -- Shutdown received");
                            }
                        }
                    }
                });
            });

            match rx.recv() {
                Ok(result) => match result {
                    Ok(()) => {
                        let elapsed_time = now.elapsed();
                        println!("elapsed_time: {:?}", elapsed_time);
                        Ok(NifRuntime {
                            rt: rt,
                            shutdown_tx: ResourceArc::new(XSender(shutdown_tx)),
                        })
                    }
                    Err(error) => Err(error.to_string()),
                },
                Err(error) => Err(error.to_string()),
            }
        }
        Err(error) => Err(error.to_string()),
    }
}

#[rustler::nif]
fn stop_runtime(runtime: NifRuntime) -> Result<(), String> {
    println!("[FRI] -- call to stop_runtime()");

    let now = std::time::Instant::now();

    match runtime.shutdown_tx.0.blocking_send(()) {
        Ok(()) => {
            let elapsed_time = now.elapsed();
            println!("elapsed_time: {:?}", elapsed_time);
            Ok(())
        }
        Err(error) => Err(error.to_string()),
    }
}

rustler::init!(
    "Elixir.Wtransport.Native",
    [start_runtime, stop_runtime],
    load = load
);
