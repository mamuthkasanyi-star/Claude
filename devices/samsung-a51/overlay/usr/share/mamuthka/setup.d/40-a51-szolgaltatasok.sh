#!/bin/bash
# Galaxy A51 eszközszolgáltatások bekapcsolása.
set -euo pipefail
systemctl enable mamuthka-sensorhub.service
systemctl enable mamuthka-hang.service
# Erőforrás-ügynök az „A51 Figyelő” Android-apphoz (port 8790, csak olvas).
systemctl enable mamuthka-eroforras.service
