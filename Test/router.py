#!/usr/bin/env python3
"""
CdM-16 Messenger — Python Router
==================================
Связующее звено между пользователями (telnet) и UART-слотами в Logisim.

Схема работы:
  - Пользователи подключаются на порты 7001, 7002, 7003, ... (CLIENT_PORTS)
  - Каждый клиентский порт соответствует одному UART-слоту в Logisim
  - Данные от пользователя → пересылаются в UART-слот (порт 8001, 8002, ...)
  - Данные из UART-слота → пересылаются пользователю

Запуск:
  python3 router.py

Конфигурация задаётся константами ниже.
"""

import asyncio
import sys
import logging
from dataclasses import dataclass, field
from typing import Optional

# =============================================================================
# Конфигурация
# =============================================================================

MAX_SLOTS = 4                     # максимум клиентов (= число UART в Logisim)

# Порты для пользователей (telnet подключается сюда)
CLIENT_BASE_PORT = 7001           # 7001, 7002, 7003, 7004

# Порты UART-слотов в Logisim (UART слушает эти порты)
UART_BASE_PORT = 8001             # 8001, 8002, 8003, 8004

LOGISIM_HOST = "127.0.0.1"       # Logisim работает локально

LOG_LEVEL = logging.INFO

# =============================================================================
# Логирование
# =============================================================================

logging.basicConfig(
    level=LOG_LEVEL,
    format="[%(asctime)s] %(levelname)s %(message)s",
    datefmt="%H:%M:%S"
)
log = logging.getLogger("cdm16-router")

# =============================================================================
# Структура слота
# =============================================================================

@dataclass
class Slot:
    index: int
    client_port: int
    uart_port: int

    # Читатель/писатель пользователя
    client_reader: Optional[asyncio.StreamReader] = None
    client_writer: Optional[asyncio.StreamWriter] = None

    # Читатель/писатель UART (Logisim)
    uart_reader: Optional[asyncio.StreamReader] = None
    uart_writer: Optional[asyncio.StreamWriter] = None

    connected: bool = False
    _tasks: list = field(default_factory=list)

    async def disconnect(self):
        self.connected = False
        for task in self._tasks:
            task.cancel()
        self._tasks.clear()
        for writer in (self.client_writer, self.uart_writer):
            if writer:
                try:
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    pass
        self.client_reader = self.client_writer = None
        self.uart_reader = self.uart_writer = None
        log.info(f"Slot {self.index}: disconnected")

# =============================================================================
# Основной класс роутера
# =============================================================================

class Messenger:
    def __init__(self):
        self.slots: list[Slot] = [
            Slot(
                index=i,
                client_port=CLIENT_BASE_PORT + i,
                uart_port=UART_BASE_PORT + i,
            )
            for i in range(MAX_SLOTS)
        ]

    # -------------------------------------------------------------------------
    # Запуск
    # -------------------------------------------------------------------------

    async def run(self):
        servers = []
        for slot in self.slots:
            server = await asyncio.start_server(
                lambda r, w, s=slot: self._on_client_connect(r, w, s),
                host="0.0.0.0",
                port=slot.client_port,
            )
            servers.append(server)
            log.info(f"Slot {slot.index}: listening for users on port {slot.client_port}")

        log.info("Router started. Connect with: telnet 127.0.0.1 <port>")
        log.info(f"  User ports: {CLIENT_BASE_PORT}–{CLIENT_BASE_PORT + MAX_SLOTS - 1}")
        log.info(f"  UART ports: {UART_BASE_PORT}–{UART_BASE_PORT + MAX_SLOTS - 1}")

        async with asyncio.TaskGroup() as tg:
            for server in servers:
                tg.create_task(server.serve_forever())

    # -------------------------------------------------------------------------
    # Обработка подключения пользователя
    # -------------------------------------------------------------------------

    async def _on_client_connect(
        self,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
        slot: Slot,
    ):
        addr = client_writer.get_extra_info("peername")
        log.info(f"Slot {slot.index}: user connected from {addr}")

        # Если слот занят — отключаем старое соединение
        if slot.connected:
            log.warning(f"Slot {slot.index}: replacing existing connection")
            await slot.disconnect()

        slot.client_reader = client_reader
        slot.client_writer = client_writer

        # Пытаемся подключиться к UART в Logisim
        try:
            uart_reader, uart_writer = await asyncio.wait_for(
                asyncio.open_connection(LOGISIM_HOST, slot.uart_port),
                timeout=5.0
            )
        except (ConnectionRefusedError, asyncio.TimeoutError) as e:
            log.error(f"Slot {slot.index}: cannot connect to UART on port {slot.uart_port}: {e}")
            msg = b"\r\n[ERROR] Logisim UART not available. Start Logisim first.\r\n"
            client_writer.write(msg)
            await client_writer.drain()
            client_writer.close()
            return

        slot.uart_reader = uart_reader
        slot.uart_writer = uart_writer
        slot.connected = True

        log.info(f"Slot {slot.index}: connected to UART on port {slot.uart_port}")

        # Запускаем два пайпа параллельно
        try:
            async with asyncio.TaskGroup() as tg:
                t1 = tg.create_task(
                    self._pipe(client_reader, uart_writer, f"slot{slot.index}:user→uart"),
                    name=f"user_to_uart_{slot.index}"
                )
                t2 = tg.create_task(
                    self._pipe(uart_reader, client_writer, f"slot{slot.index}:uart→user"),
                    name=f"uart_to_user_{slot.index}"
                )
                slot._tasks = [t1, t2]
        except* Exception as eg:
            for exc in eg.exceptions:
                if not isinstance(exc, asyncio.CancelledError):
                    log.debug(f"Slot {slot.index}: pipe error: {exc}")

        await slot.disconnect()

    # -------------------------------------------------------------------------
    # Пайп: читаем из reader, пишем в writer
    # -------------------------------------------------------------------------

    @staticmethod
    async def _pipe(
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        label: str,
        chunk_size: int = 256,
    ):
        try:
            while True:
                data = await reader.read(chunk_size)
                if not data:
                    log.debug(f"[{label}] EOF")
                    break
                writer.write(data)
                await writer.drain()
                log.debug(f"[{label}] {len(data)} bytes")
        except (ConnectionResetError, BrokenPipeError, asyncio.IncompleteReadError):
            log.debug(f"[{label}] connection closed")
        except asyncio.CancelledError:
            raise

# =============================================================================
# Точка входа
# =============================================================================

def main():
    print("=" * 60)
    print("  CdM-16 Messenger Router")
    print("  Запустите Logisim со схемой messenger.circ ПЕРВЫМ")
    print("=" * 60)

    router = Messenger()
    try:
        asyncio.run(router.run())
    except KeyboardInterrupt:
        log.info("Router stopped.")

if __name__ == "__main__":
    main()
