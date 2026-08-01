<p align="center">
  <img src="banner.png" alt="NodeTest32 — тестер нод VPN" width="100%">
</p>

# NodeTest32

Меню проверки ноды VPN от [Manual32](https://manual32.online). Проверенные инструменты в одном месте: аудит сервера, скорость до РФ, DPI/ТСПУ, репутация и регион IP, железо. Запускаешь на своей ноде, выбираешь номер — получаешь результат.

## Запуск

Меню одной командой:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh)
```

Поставить как команду `nodetest32` (потом запускать откуда угодно):

```bash
bash <(curl -sL https://raw.githubusercontent.com/bini69-oi/NodeTest32/main/nodetest32.sh) --install
```

При первом запуске тестер один раз сам ставит всё нужное (iperf3, sysbench, модули проверок) — дальше стартует моментально и ничего лишнего не качает.

## Что проверяет

| # | Тест | Что показывает |
|---|------|----------------|
| 1 | Сквозная проверка по ссылке | реально ли идёт трафик через ноду: выходной IP, задержка, скорость, доступность сайтов (запускать с чистой машины) |
| 2 | Аудит сервера | KVM/контейнер, стил (оверселл), AES-NI, RAM/диск/swap, BBR, IPv6, время |
| 3 | Скорость до РФ | iperf3 до серверов внутри России |
| 4 | DPI / ТСПУ | палится ли нода на российском DPI |
| 5 | Геоблокировки | что режется с этого адреса |
| 6 | Репутация IP | блок-листы и чистота адреса |
| 7 | Регион по IP | какую страну видят сервисы |
| 8 | Железо: CPU / диск / сеть | полный бенчмарк сервера |
| 9 | Тест CPU | быстрый бенч процессора |
| 10 | Сводка сервера | параметры + скорость |

Любой тест — по номеру, или пункт **«Общая проверка»** прогонит всё подряд.

## Целостность

Модули проверок подтягиваются один раз с зафиксированной версии и сверяются по контрольной сумме (`ext/manifest`) перед запуском. Под капотом используются открытые проекты — спасибо авторам: [xray-knife](https://github.com/lilendian0x00/xray-knife), [ipregion](https://github.com/vernette/ipregion), [censorcheck](https://github.com/vernette/censorcheck), [russian-iperf3-servers](https://github.com/itdoginfo/russian-iperf3-servers), [YABS](https://github.com/masonr/yet-another-bench-script), [IPQuality](https://github.com/xykt/IPQuality), [bench.sh](https://github.com/teddysun/across).

---

Manual32 · мануалы по своему VPN
