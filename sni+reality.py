import socket
import ssl
import time

SERVER_IP = "202.155.94.63"
SERVER_PORT = 11443
TIMEOUT = 3.0

SNI_LIST = [
    "zenius.net",
    "www.zenius.net",
    "www.google.com",
    "www.cloudflare.com",
]

def probe_sni(sni):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    start = time.time()
    try:
        sock = socket.create_connection(
            (SERVER_IP, SERVER_PORT), timeout=TIMEOUT
        )
        tls = ctx.wrap_socket(
            sock,
            server_hostname=sni,
            do_handshake_on_connect=False
        )

        # kirim ClientHello saja
        tls.do_handshake()

    except ssl.SSLError as e:
        elapsed = int((time.time() - start) * 1000)
        # handshake error cepat = SNI lolos tapi server Reality tidak lanjut
        return ("PASS", elapsed)

    except ConnectionResetError:
        return ("RESET", None)

    except socket.timeout:
        return ("TIMEOUT", None)

    except Exception:
        return ("FAIL", None)

    return ("UNKNOWN", None)


if __name__ == "__main__":
    print("SNI".ljust(30), "RESULT", "RTT(ms)")
    print("-" * 50)
    for sni in SNI_LIST:
        res, rtt = probe_sni(sni)
        print(sni.ljust(30), res, rtt if rtt else "-")
