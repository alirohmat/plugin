import socket
import time
import struct

SERVER_IP = "202.155.94.63"
SERVER_PORT = 11443
TIMEOUT = 3

SNI_LIST = [
    "zenius.net",
    "www.zenius.net",
    "www.google.com",
    "www.cloudflare.com",
]

def build_client_hello(sni):
    # TLS 1.2 ClientHello minimal + SNI
    sni_bytes = sni.encode()
    server_name = b"\x00" + struct.pack("!H", len(sni_bytes)) + sni_bytes
    server_name_list = struct.pack("!H", len(server_name)) + server_name
    sni_ext = (
        b"\x00\x00" +
        struct.pack("!H", len(server_name_list) + 2) +
        server_name_list
    )

    extensions = sni_ext
    extensions_len = struct.pack("!H", len(extensions))

    handshake = (
        b"\x01" +                # ClientHello
        b"\x00\x00\x00" +         # length placeholder
        b"\x03\x03" +             # TLS 1.2
        b"\x00" * 32 +             # random
        b"\x00" +                  # session id
        b"\x00\x02\x13\x01" +      # cipher suites
        b"\x01\x00" +              # compression
        extensions_len +
        extensions
    )

    handshake = handshake[:1] + struct.pack("!I", len(handshake) - 4)[1:] + handshake[4:]

    record = (
        b"\x16\x03\x01" +
        struct.pack("!H", len(handshake)) +
        handshake
    )

    return record

def probe_sni(sni):
    data = build_client_hello(sni)
    start = time.time()

    try:
        sock = socket.create_connection((SERVER_IP, SERVER_PORT), timeout=TIMEOUT)
        sock.sendall(data)

        sock.settimeout(1)
        try:
            sock.recv(1)
            return "PASS", int((time.time() - start) * 1000)
        except socket.timeout:
            return "PASS", int((time.time() - start) * 1000)

    except ConnectionResetError:
        return "RESET", None
    except socket.timeout:
        return "TIMEOUT", None
    except Exception:
        return "FAIL", None
    finally:
        try:
            sock.close()
        except:
            pass

if __name__ == "__main__":
    print("SNI".ljust(30), "RESULT", "RTT(ms)")
    print("-" * 50)
    for sni in SNI_LIST:
        res, rtt = probe_sni(sni)
        print(sni.ljust(30), res, rtt if rtt else "-")
