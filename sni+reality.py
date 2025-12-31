import socket
import time
import struct

SERVER_IP = "202.155.94.63"
SERVER_PORT = 11443
CONNECT_TIMEOUT = 3
WAIT_AFTER_SEND = 2

SNI_LIST = [
    "zenius.net",
    "www.zenius.net",
    "www.google.com",
    "www.cloudflare.com",
]

def build_client_hello(sni):
    sni_bytes = sni.encode()
    server_name = b"\x00" + struct.pack("!H", len(sni_bytes)) + sni_bytes
    server_name_list = struct.pack("!H", len(server_name)) + server_name
    sni_ext = b"\x00\x00" + struct.pack("!H", len(server_name_list) + 2) + server_name_list

    extensions = sni_ext
    extensions_len = struct.pack("!H", len(extensions))

    handshake = (
        b"\x01" +
        b"\x00\x00\x00" +
        b"\x03\x03" +
        b"\x00" * 32 +
        b"\x00" +
        b"\x00\x02\x13\x01" +
        b"\x01\x00" +
        extensions_len +
        extensions
    )

    handshake = handshake[:1] + struct.pack("!I", len(handshake) - 4)[1:] + handshake[4:]

    record = b"\x16\x03\x01" + struct.pack("!H", len(handshake)) + handshake
    return record

def probe_sni(sni):
    debug = {}
    start = time.time()

    try:
        sock = socket.create_connection(
            (SERVER_IP, SERVER_PORT),
            timeout=CONNECT_TIMEOUT
        )
        debug["tcp_connect_ms"] = int((time.time() - start) * 1000)

        data = build_client_hello(sni)
        sock.sendall(data)
        debug["client_hello_sent"] = True

        sock.settimeout(WAIT_AFTER_SEND)
        try:
            recv_start = time.time()
            data = sock.recv(1)
            debug["server_response"] = "DATA"
            debug["response_delay_ms"] = int((time.time() - recv_start) * 1000)
            result = "RESPOND"
        except socket.timeout:
            debug["server_response"] = "NO_RESPONSE"
            result = "PASS"
        except ConnectionResetError:
            debug["server_response"] = "RST"
            result = "RESET"

    except ConnectionResetError:
        result = "RESET_EARLY"
    except socket.timeout:
        result = "CONNECT_TIMEOUT"
    except Exception as e:
        result = "ERROR"
        debug["error"] = str(e)
    finally:
        try:
            sock.close()
        except:
            pass

    debug["total_time_ms"] = int((time.time() - start) * 1000)
    return result, debug

if __name__ == "__main__":
    for sni in SNI_LIST:
        result, dbg = probe_sni(sni)
        print("\nSNI:", sni)
        print("RESULT:", result)
        for k, v in dbg.items():
            print(f"  {k}: {v}")
