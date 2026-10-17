#!/bin/bash
# Galaxy A51 eszközszolgáltatások bekapcsolása.
set -euo pipefail
systemctl enable mamuthka-sensorhub.service
systemctl enable mamuthka-hang.service
