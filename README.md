# Умный аквариум

Flutter-приложение для мониторинга и управления аквариумом через ESP.

## Возможности

- показ температуры, уровня воды и состояния устройств;
- управление светом, кормушкой, компрессором и чисткой;
- несколько аквариумов с отдельными IP ESP;
- быстрые команды `Refresh` и `Emergency OFF`;
- пресеты Day, Night и Feed;
- история команд, показаний и опасностей;
- настройка темы и демо-режима.

## Экраны

- `Home` - состояние выбранного аквариума и управление.
- `Aquarium` - список аквариумов, добавление, удаление и IP ESP.
- `History` - фильтр и сортировка событий.
- `Settings` - тема, демо-режим и версия.

## ESP API

```text
GET /status
GET /analytics
GET /led?state=on|off
GET /motor?state=on|off&dir=forward|back
GET /compressor?state=on|off
GET /clean
```

Основные поля `/status`:

```json
{
  "led": true,
  "temp": 19.5,
  "levelPercent": 90,
  "pump": false,
  "compressor": true,
  "mode": "IDLE",
  "time": "12:00:00",
  "timeSynced": true,
  "historyCount": 10,
  "cleanProgress": 0,
  "canClean": true,
  "motor": 0
}
```

## Запуск

```bash
flutter pub get
flutter run
```

Проверка:

```bash
flutter test
flutter analyze
```
