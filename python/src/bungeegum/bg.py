"""Bungeegum: Android in memory execution toolkit"""

import argparse
import logging
import sys
import threading
import time
import typing

import adbutils
import frida
import importlib_resources as pkg_resources
from frida.core import Device as FridaDevice

logging.basicConfig(level=logging.INFO)

APK_DBG = "com.zetier.bungeegum-debug.apk"
EXEC_SCRIPT = "fork_exec.js"
SHELLCODE_SCRIPT = "run_shellcode.js"
BG_PKG = "com.zetier.bungeegum"
BG_APP_NAME = "Bungeegum"
BG_PY_PKG = "bungeegum"
MAIN_ACTIVITY = BG_PKG + "/.BgActivity"
LOCALHOST = "127.0.0.1"
DEFAULT_ADB_SERVER_PORT = 5037


def parse_args() -> argparse.Namespace:
    """CLI argument parser"""

    parser = argparse.ArgumentParser(
        description="Execute code within an application context"
    )

    parser.add_argument(
        "-d", "--device", type=str, default=None, help="ADB device ID to run on"
    )
    parser.add_argument(
        "-r",
        "--remote",
        action="store_true",
        help="Set if the file to be executed is on the device",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "-s", "--shellcode", type=str, help="Shellcode file to execute on the device"
    )
    group.add_argument(
        "-e", "--elf", type=str, help="ELF file to execute on the device"
    )

    parser.add_argument(
        "-a",
        "--args",
        nargs=argparse.REMAINDER,
        default=[],
        help="Optional args to pass to the ELF file",
    )

    args = parser.parse_args()

    if args.remote and args.shellcode:
        parser.error("Remote file path is only allowed in ELF mode.")

    if args.args and args.shellcode:
        parser.error("Args for shellcode are not yet supported.")

    return args


def get_device(device_id: typing.Optional[str]) -> adbutils.AdbDevice:
    """Connect to target ADB device
    Args:
        device_id: ID of device (via `adb devices`)
    Returns:
        device: ADB device object
    """
    client = adbutils.AdbClient(host=LOCALHOST, port=DEFAULT_ADB_SERVER_PORT)
    device_list = client.device_list()
    if not device_list:
        raise adbutils.errors.AdbError("no connected devices found")

    if len(device_list) > 1 and not device_id:
        raise adbutils.errors.AdbError(
            "Multiple devices connected. Please specify with --device"
        )

    target_device = client.device(device_id)
    return target_device


def install_and_attach(
    device: adbutils.AdbDevice,
    frida_device: FridaDevice,
    apk_path: str,
    package_name: str,
    process_name: str,
    max_retries: int = 5,
) -> frida.core.Session:
    """
    Attempts to install the given APK and attach a Frida session to it.

    Args:
        device: An AdbDevice object representing the ADB device.
        apk_path: The file path of the APK to install.
        package_name: The package name of the app.
        max_retries: The maximum number of retries to attempt attaching the session.

    Returns:
        The Frida session if successful.

    Raises:
        Exception: If unable to attach session after maximum retries.
    """
    installed_packages = device.shell("pm list packages").split("\n")
    installed_packages = [pkg.replace("package:", "") for pkg in installed_packages]

    if package_name not in installed_packages:
        logging.info("App package not installed. Attempting to install...")
        ref = pkg_resources.files("bungeegum") / apk_path
        with pkg_resources.as_file(ref) as path:
            device.install(str(path), flags=["-r", "-t", "-g"])
        time.sleep(5)  # Give some time for the package manager to finish its work

    retry_count = 0
    while retry_count < max_retries:
        try:
            logging.debug("Attempting to attach to %r...", process_name)
            session = frida_device.attach(process_name)
            return session
        except (frida.ProcessNotFoundError, frida.ServerNotRunningError):
            logging.warning(
                "Failed to attach to the app process. Retrying (%i/%i)...",
                retry_count + 1,
                max_retries,
            )
            device.app_start(BG_PKG)
            retry_count += 1
            time.sleep(3)  # Give some time for the process to start

    raise frida.ProcessNotFoundError(
        f"Failed to attach session after {max_retries} retries."
    )


def main() -> int:
    """Run a BG session"""
    ret = 1

    args = parse_args()

    adb_device = get_device(args.device)
    logging.debug("Found adb device: %s", adb_device.serial)

    frida_device = frida.get_device(adb_device.serial, timeout=10)
    logging.info("Created Frida device: %r", frida_device)

    session = install_and_attach(
        adb_device, frida_device, APK_DBG, BG_PKG, BG_APP_NAME, 10
    )

    logging.info("Successfully connected to target process")

    script_args = {}
    if args.shellcode:
        logging.info("Running shellcode: %s", args.shellcode)
        target_script = SHELLCODE_SCRIPT
        target_path = args.shellcode
    else:
        logging.info("Running ELF: %s", args.elf)
        target_script = EXEC_SCRIPT
        # Set arguments for ELF
        script_args["args"] = args.args
        target_path = args.elf

    if args.remote:
        logging.debug("Running in remote mode")
        # If we want to run a file from the target device,
        # simply provide the path on disk to the Frida script
        script_args["path"] = target_path
    else:
        logging.debug("Running in local mode")
        # Otherwise, we open the provided local file and
        # pass it in as a bytearray
        try:
            with open(target_path, "rb") as local_file:
                data_bytes = local_file.read()
        except OSError:
            logging.exception("Failed to open file")
            sys.exit(ret)
        script_args["data"] = list(data_bytes)

    try:
        with pkg_resources.path(BG_PY_PKG, target_script) as path:
            with open(path, "r", encoding="utf-8") as js_file:
                contents = js_file.read()
    except OSError:
        logging.exception("Failed to read file")
        sys.exit(ret)

    script = session.create_script(contents)

    script_done = threading.Event()

    # Callback for when we receive a message from Frida script
    def on_message(message: typing.Dict[str, typing.Any], _data: typing.Optional[bytes]) -> None:
        # Use ret var from outer function
        nonlocal ret
        logging.debug("Received message from JS: %s", message)

        if message.get("type") == "error":
            logging.error("Frida script error: %s", message)
            script_done.set()
            return

        payload = message.get("payload")

        if payload == "status":
            logging.debug("Sending args")
            script.post({"type": "args", "payload": script_args})

        elif isinstance(payload, dict) and payload.get("type") == "stdout":
            if _data:
                sys.stdout.buffer.write(_data)
                sys.stdout.buffer.flush()

        elif isinstance(payload, int):
            logging.debug("Received result from JS: %s", message["payload"])
            ret = message.get("payload")  # type: ignore
            script_done.set()

    script.on("message", on_message)
    # Set up script to send message to on_message
    logging.debug("Running Frida script in target app")
    script.load()
    script_done.wait()
    session.detach()
    logging.info("Returned status: %d", ret)

    return ret


if __name__ == "__main__":
    sys.exit(main())
