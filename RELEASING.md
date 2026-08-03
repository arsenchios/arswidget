# Выпуск ArsWidget

## Что готово

- ArsWidget проверяет ленту обновлений каждые шесть часов и по кнопке
  «Проверить обновления».
- Обновления публикуются в GitHub Releases, а лента доступна через GitHub Pages.
- Архив каждого обновления подписывается Sparkle EdDSA-ключом. Приватный ключ
  хранится только в Keychain владельца и в GitHub Secret.

## Один раз перед первым выпуском

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

## Выпуск

В GitHub открыть `Actions` -> `Выпуск обновления ArsWidget` -> `Run workflow`.
Указать, например, версию `0.1.0` и короткий список изменений.

Через несколько минут появится GitHub Release. Установленный ArsWidget покажет
предложение скачать обновление. Пользователь подтверждает установку и
перезапуск; без Apple Developer первая установка может потребовать ручного
подтверждения macOS.
