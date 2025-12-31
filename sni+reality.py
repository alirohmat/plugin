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

def test_sni(sni):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    start = time.time()
    try:
        sock = socket.create_connection(
            (SERVER_IP, SERVER_PORT), timeout=TIMEOUT
        )
        tls = ctx.wrap_socket(sock, server_hostname=sni)
        tls.do_handshake()
        rtt = int((time.time() - start) * 1000)
        tls.close()
        return ("OK", rtt)
    except ssl.SSLError:
        return ("BLOCKED", None)
    except socket.timeout:
        return ("TIMEOUT", None)
    except ConnectionResetError:
        return ("RESET", None)
    except Exception:
        return ("FAIL", None)

if __name__ == "__main__":
    print("SNI\t\t\tRESULT\tRTT(ms)")
    print("-" * 40)
    for sni in SNI_LIST:
        result, rtt = test_sni(sni)
        print(f"{sni:<20}\t{result}\t{rtt if rtt else '-'}")
