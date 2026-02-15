# Auto-Proxy-Setup

**Automated installer for Dante (SOCKS5) + Nginx SNI proxy on Linux. Bypass geo-blocks with your own VPS. Interactive script sets up secure proxy server in minutes. Supports password auth, firewall config, and real-time testing. Perfect for privacy enthusiasts and self-hosters.**

---

##  Зачем это нужно

Этот скрипт ставит на твой VPS два сервиса:

1. **Dante (SOCKS5)** — универсальный прокси для браузера, системы или любых приложений.
2. **Nginx (SNI proxy)** — прокси для HTTPS трафика. Позволяет открывать сайты просто через `hosts` файл, без настройки прокси в системе.

Оба работают через твой VPS, маскируя твой реальный IP.

---

## Что входит в установку

- ✅ Dante SOCKS5 сервер (порт `1080`)
- ✅ Nginx с модулем `stream` для SNI-прокси (порт `443`)
- ✅ Авторизация по паролю (опционально)
- ✅ Автоопределение сетевого интерфейса
- ✅ Настройка iptables (закрыто всё, кроме нужных портов)
- ✅ Проверка работоспособности после установки
- ✅ Полная интерактивность — отвечаешь на вопросы и идешь пить чай

---

## Требования

- Чистый сервер на **Debian** или **Ubuntu**
- Права **root** (или `sudo`)
- VPS с белым IP в Европе (Германия, Финляндия, Нидерланды — идеально)
- Минимум 512 MB RAM, 1 CPU (хватит с головой)

---

## Быстрый старт

```bash
git clone https://github.com/Kuos-Lian/Auto-Proxy-Setup.git
cd Auto-Proxy-Setup
chmod +x install.sh
sudo ./install.sh
