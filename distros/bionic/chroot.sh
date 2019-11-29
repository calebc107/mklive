#!/bin/bash
apt update
apt install live-boot linux-generic locales
dpkg-reconfigure locales
passwd -d root
