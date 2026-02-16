# Auto Dante SOCKS5 Installer

**Автоматическая установка Dante SOCKS5 на Debian/Ubuntu.  
Без лишнего. Без SNI-прокси. Без REALITY. Просто рабочий SOCKS5 за 5 минут.**

---

Если завтра SOCKS5 начнут резать — вернёмся к XRay. Но пока — **KISS** (Keep It Simple, Stupid).

---

## Что входит

- ✅ Dante (SOCKS5) на порту `1080`
- ✅ Поддержка авторизации по паролю (опционально)
- ✅ Настройка iptables (закрыто всё, кроме SSH и SOCKS5)
- ✅ Менеджмент-меню: можно удалить, перенастроить, сменить пароль, изменить белый IP
- ✅ Работает на **чистой Debian/Ubuntu** без предустановленных пакетов

---

## Быстрый старт

```bash
git clone https://github.com/Kuos-Lian/Auto-Proxy-Setup.git
cd Auto-Proxy-Setup
chmod +x dante-manager.sh
sudo ./dante-manager.sh
