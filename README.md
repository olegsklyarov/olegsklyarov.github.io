# Oleg Sklyarov Notes

Инженерная база знаний, опубликованная на [GitHub Pages](https://olegsklyarov.github.io/) через [MkDocs](https://www.mkdocs.org/) и [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).

## Локальный запуск

Установите зависимости:

```bash
pip install -r requirements.txt
```

Запустите локальный сервер с автоперезагрузкой:

```bash
mkdocs serve
```

Сайт будет доступен по адресу [http://127.0.0.1:8000/](http://127.0.0.1:8000/).

Собрать статический сайт в каталог `site/`:

```bash
mkdocs build
```

## Публикация изменений

1. Добавьте или отредактируйте страницы в каталоге `docs/`.
1. При необходимости обновите навигацию в `mkdocs.yml`.
1. Закоммитьте изменения и отправьте их в ветку `main`:

```bash
git add .
git commit -m "Update documentation"
git push
```

После успешного выполнения GitHub Actions workflow сайт автоматически обновится на [https://olegsklyarov.github.io/](https://olegsklyarov.github.io/).

## Структура проекта

```
.
├── docs/                  # Исходники страниц
├── mkdocs.yml             # Конфигурация MkDocs
├── requirements.txt       # Python-зависимости
└── .github/workflows/     # CI/CD для GitHub Pages
```
