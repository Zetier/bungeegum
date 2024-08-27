# Bungeegum

Bungeegum is a set of tools designed to test code execution payloads within the
context of a standard Android application. By leveraging the powerful
[Frida](https://frida.re/docs/home/) instrumentation framework, it precisely
replicates the runtime conditions of an Android app, simulating the execution
of ELFs or shellcode as though they were triggered by a remote code execution
exploit.

## Prerequisites

- Python 3.8 or higher
- [Docker](https://docs.docker.com/get-docker/)

## Install

Note: Bungeegum is developed on and regularly tested with Ubuntu 18.04 and
Python 3.8. Other distributions and versions may work, but are currently
untested.

1. Clone the repository

2. Install dependencies

    ```sh
    sudo apt-get update
    sudo apt-get install python3-venv python3.8-venv make wget xz-utils -y
    python3.8 -m venv venv
    source venv/bin/activate
    (venv) pip install --upgrade pip
    ```

3. Build the APK and install the Python package by running the `make` command:

    ```sh
    make
    ```

## Supported Android Versions

Bungeegum has been tested successfully on Android 7, 9, 11, and 12.

## Usage

```sh
(venv) bungeegum -h
usage: bungeegum [-h] -d DEVICE [-r] (-s SHELLCODE | -e ELF) [-a [ARGS [ARGS ...]]]

Execute code within an application context

optional arguments:
  -h, --help            show this help message and exit
  -d DEVICE, --device DEVICE
                        ADB device ID to run on
  -r, --remote          Set if the file to be executed is on the device
  -s SHELLCODE, --shellcode SHELLCODE
                        Shellcode file to execute on the device
  -e ELF, --elf ELF     ELF file to execute on the device
  -a [ARGS [ARGS ...]], --args [ARGS [ARGS ...]]
                        Optional args to pass to the ELF file
```

## Examples

- Run an ELF from the host on the device:

```sh
bungeegum --elf ~/my_elf/arm64-v8a/my_elf
```

- Run a shellcode blob on the device

```sh
bungeegum --shellcode ~/my_shellcode.bin
```

- Run an on-device ELF:

```sh
bungeegum --remote --elf /system/bin/log --args "hello world"
```

## Contributing

Contributions are welcome! If you find any issues or have suggestions for
improvements, please open an issue or submit a pull request.

## License

This project is licensed under the GPLv2 License.
