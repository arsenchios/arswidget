# Выпуск ArsWidget

## Первый выпуск

- GitHub Actions собирает ZIP с приложением и публикует его в GitHub Releases.
- Такой ZIP можно скачать, перенести `ArsWidget.app` в `Applications` и открыть
  без Xcode.
- Автообновления отключены, пока не создан отдельный подписанный канал ArsWidget.

## Автообновления, когда они понадобятся

1. Убедиться, что репозиторий публичный и GitHub Pages включён из GitHub Actions.
2. В GitHub: `Settings` -> `Secrets and variables` -> `Actions` -> `New repository secret`.
3. Создать секрет `ARSWIDGET_SPARKLE_PRIVATE_KEY`.
4. Экспортировать ключ только на своём Mac и сразу удалить временный файл:

```sh
generate_keys --account ArsWidget.production -x /tmp/arswidget-sparkle-key
cat /tmp/arswidget-sparkle-key
rm /tmp/arswidget-sparkle-key
```

Скопировать выведенное содержимое в GitHub Secret. Никогда не добавлять этот
ключ в репозиторий, сообщения или публичные файлы.

## Выпуск ZIP

В GitHub открыть `Actions` -> `Выпуск обновления ArsWidget` -> `Run workflow`.
Указать, например, версию `0.1.0` и короткий список изменений.

Через несколько минут появится GitHub Release. Скачать ZIP можно без Xcode.
Без Apple Developer macOS при первом запуске может попросить ручное
подтверждение через правый клик по приложению -> «Открыть».

После настройки Sparkle новый ZIP также будет подписан для автообновления.
