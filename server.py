import socket
import threading

HOST = '0.0.0.0'
PORT = 7241

def relay(src, dst):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                break
            dst.sendall(data)
    except:
        pass
    finally:
        try:
            src.shutdown(socket.SHUT_RDWR)
        except:
            pass
        try:
            dst.shutdown(socket.SHUT_RDWR)
        except:
            pass
        src.close()
        dst.close()

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((HOST, PORT))
    srv.listen(2)

    while True:
        print(f"Ждём первого клиента на {PORT}...")
        a, addr_a = srv.accept()
        print(f"Первый подключился: {addr_a}")

        print(f"Ждём второго клиента на {PORT}...")
        b, addr_b = srv.accept()
        print(f"Второй подключился: {addr_b}")

        t1 = threading.Thread(target=relay, args=(a, b), daemon=True)
        t2 = threading.Thread(target=relay, args=(b, a), daemon=True)

        t1.start()
        t2.start()

        t1.join()
        t2.join()
        print("Сессия завершена")

if __name__ == '__main__':
    main()