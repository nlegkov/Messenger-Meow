import socket
import threading

A2_TX = ("10.151.150.217", 9000)
B2_RX = ("10.151.150.217", 9001)

A1_TX = ("10.151.150.201", 8000)
B1_RX = ("10.151.150.201", 8001)

sa1 = socket.create_connection(A1_TX)
sb1 = socket.create_connection(B1_RX)

sa2 = socket.create_connection(A2_TX)
sb2 = socket.create_connection(B2_RX)

def forward(src, dst):
    while True:
        data = src.recv(1024)
        if not data:
            break
        print(data)
        dst.sendall(data)

threading.Thread(target=forward, args=(sa1, sb2)).start()
threading.Thread(target=forward, args=(sb2, sa1)).start()

threading.Thread(target=forward, args=(sa2, sb1)).start()
threading.Thread(target=forward, args=(sb1, sa2)).start()

print("Bridge running")

input()