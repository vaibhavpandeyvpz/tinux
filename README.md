# Tinux
Using Tinux, you can build your very own, tiny ([Busybox](https://busybox.net/) based) [Linux](https://kernel.org/) distribution.

[![Screenshot](https://raw.githubusercontent.com/vaibhavpandeyvpz/tinux/master/screenshot.png)](https://raw.githubusercontent.com/vaibhavpandeyvpz/tinux/master/screenshot.png)

### Requirements
Before starting to build, you will need to have dependencies installed on your build machine. Running below command will help you install it on most [Ubuntu](https://ubuntu.com/) based machines but you may easily adapt it to operating system of your choice if you now it well.

```bash
sudo apt install bison build-essential flex libelf-dev libncurses-dev libssl-dev qemu qemu-kvm xz-utils
```

### Building
Navigate into the `Tinux` folder, and run command as follows:

```bash
./build.sh 5.0.10 1.30.0 # ./build.sh <kernel-version> <busybox-version>
```

It will then download the [Linux](https://kernel.org/) kernel and [Busybox](https://busybox.net/) for the version you have supplied. Then extract & build those along with a basic *initramfs* image. Once built, you can optionally boot it if you installed [Qemu](https://www.qemu.org/) in first step.
