---
git_creation_date_localized: "2026-06-08"
---

# ActiveRecord без Rails

## Введение

ActiveRecord — это ORM-слой Rails, но он не привязан к полноценному фреймворку. Пакет `activerecord` можно использовать как самостоятельную библиотеку в Ruby-скриптах, rake-задачах, консольных утилитах и микросервисах, где нужен удобный доступ к PostgreSQL без поднятия всего стека Rails.

Типичные сценарии:

- миграция данных между системами;
- одноразовые административные скрипты;
- фоновые воркеры, которым нужен только доступ к БД;
- прототипирование SQL-запросов с объектной моделью поверх существующей схемы.

В этой заметке разберём минимальный рабочий пример: подключение к PostgreSQL, описание модели, чтение и запись данных, а также нюансы управления соединениями.

## Задача

Предположим, в PostgreSQL уже есть таблица `users` со следующей схемой:

```sql
CREATE TABLE users (
  id         BIGSERIAL PRIMARY KEY,
  email      VARCHAR(255) NOT NULL UNIQUE,
  name       VARCHAR(255),
  active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

Нужно написать Ruby-скрипт, который:

1. Подключается к базе `app_development`.
2. Находит активных пользователей.
3. Создаёт новую запись.
4. Корректно закрывает соединения при завершении.

Для этого достаточно `activerecord` и драйвера `pg`.

## Подключение к PostgreSQL

Создайте `Gemfile`:

```ruby
source "https://rubygems.org"

gem "activerecord", "~> 8.0"
gem "pg", "~> 1.5"
```

Установите зависимости:

```bash
bundle install
```

Строка подключения для PostgreSQL обычно выглядит так:

```ruby
DATABASE_URL = "postgresql://postgres:secret@localhost:5432/app_development"
```

Либо можно передать параметры по отдельности:

```ruby
{
  adapter:  "postgresql",
  host:     "localhost",
  port:     5432,
  database: "app_development",
  username: "postgres",
  password: "secret"
}
```

## establish_connection

`ActiveRecord::Base.establish_connection` создаёт пул соединений и делает его доступным для всех моделей, наследующих `ActiveRecord::Base`.

```ruby
require "active_record"

ActiveRecord::Base.establish_connection(
  adapter:  "postgresql",
  host:     "localhost",
  database: "app_development",
  username: "postgres",
  password: "secret"
)
```

Если используется `DATABASE_URL`, достаточно одной строки:

```ruby
ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL"))
```

После вызова `establish_connection` ActiveRecord готов выполнять SQL через модели. Отдельно поднимать Rails-приложение не нужно.

## Создание модели

Модель — это Ruby-класс, который маппится на таблицу. По умолчанию имя таблицы выводится из имени класса: `User` → `users`.

```ruby
class User < ActiveRecord::Base
  # Таблица users уже существует — миграции не нужны.
end
```

Если имя таблицы нестандартное, укажите его явно:

```ruby
class User < ActiveRecord::Base
  self.table_name = "app_users"
end
```

Для существующей legacy-схемы можно отключить автоматические timestamp-колонки, если их нет:

```ruby
class LegacyOrder < ActiveRecord::Base
  self.table_name = "orders"
  self.record_timestamps = false
end
```

## Исследование схемы таблицы

ActiveRecord умеет читать метаданные из PostgreSQL через `connection` и `columns`.

Список колонок:

```ruby
User.columns.each do |column|
  puts "#{column.name}: #{column.type}, null: #{column.null}"
end
```

Пример вывода:

```
id: integer, null: false
email: string, null: false
name: string, null: true
active: boolean, null: false
created_at: datetime, null: false
updated_at: datetime, null: false
```

Проверить, существует ли таблица:

```ruby
ActiveRecord::Base.connection.table_exists?(:users)
# => true
```

Получить SQL-тип колонки:

```ruby
User.columns_hash["email"].sql_type
# => "character varying(255)"
```

Это удобно при работе с чужой схемой, когда документации нет, а нужно быстро понять структуру данных.

## Поиск записей

ActiveRecord генерирует параметризованные SQL-запросы, защищая от SQL-инъекций.

```ruby
# Все активные пользователи
User.where(active: true)

# Один пользователь по email
User.find_by(email: "alice@example.com")

# Первые 10 записей, отсортированные по id
User.order(:id).limit(10)

# Подсчёт
User.where(active: true).count
```

Сгенерированный SQL для `User.where(active: true)`:

```sql
SELECT "users".* FROM "users" WHERE "users"."active" = TRUE
```

Для сложных условий можно использовать Arel или сырой SQL с биндингами:

```ruby
User.where("created_at > ?", 1.week.ago)
User.where("name ILIKE ?", "%alice%")
```

`find` по первичному ключу бросает `ActiveRecord::RecordNotFound`, если запись не найдена. `find_by` возвращает `nil`.

## Вставка данных

Создание одной записи:

```ruby
user = User.create!(
  email: "bob@example.com",
  name:  "Bob",
  active: true
)
```

`create!` валидирует объект и бросает исключение при ошибке. Безопасный вариант без исключения — `create`.

Массовая вставка через `insert_all` (Rails 6+), минуя callbacks и validations:

```ruby
User.insert_all([
  { email: "carol@example.com", name: "Carol", active: true, created_at: Time.now, updated_at: Time.now },
  { email: "dave@example.com",  name: "Dave",  active: true, created_at: Time.now, updated_at: Time.now }
])
```

Обновление:

```ruby
user = User.find_by!(email: "bob@example.com")
user.update!(name: "Robert")
```

Транзакция:

```ruby
ActiveRecord::Base.transaction do
  user = User.create!(email: "eve@example.com", name: "Eve")
  user.update!(active: false)
end
```

## Сравнение с psql

Тот же результат в `psql`:

```sql
-- Поиск
SELECT * FROM users WHERE active = TRUE;

-- Вставка
INSERT INTO users (email, name, active, created_at, updated_at)
VALUES ('bob@example.com', 'Bob', TRUE, NOW(), NOW());

-- Обновление
UPDATE users SET name = 'Robert', updated_at = NOW()
WHERE email = 'bob@example.com';
```

| Аспект | ActiveRecord | psql |
|--------|--------------|------|
| Параметризация | Автоматическая | Ручная (`$1`, `$2`) |
| Маппинг на объекты | Встроенный | Нет |
| Callbacks / validations | Да | Нет |
| Скорость для разовых задач | Ниже (overhead ORM) | Выше |
| Переносимость логики | Ruby-код | SQL-скрипты |

ActiveRecord оправдан, когда логика сложная, нужны транзакции на уровне объектов или код будет переиспользован. Для простого `SELECT COUNT(*)` быстрее и прозрачнее чистый SQL.

## Где живёт соединение

После `establish_connection` соединение хранится в пуле внутри `ActiveRecord::Base.connection_handler`. Каждый поток получает своё соединение из пула при первом обращении к БД.

```ruby
ActiveRecord::Base.connection_pool
# => #<ActiveRecord::ConnectionAdapters::ConnectionPool ...>
```

Текущее соединение потока:

```ruby
ActiveRecord::Base.connection
```

Несколько моделей, наследующих `ActiveRecord::Base`, разделяют один пул, если не указано иное через `establish_connection` на уровне класса.

Для второй базы данных создайте абстрактный класс:

```ruby
class AnalyticsRecord < ActiveRecord::Base
  self.abstract_class = true
  establish_connection ENV.fetch("ANALYTICS_DATABASE_URL")
end

class Event < AnalyticsRecord
end
```

## Connection Pool

Пул ограничивает число одновременных соединений с PostgreSQL. По умолчанию `pool: 5`.

```ruby
ActiveRecord::Base.establish_connection(
  adapter: "postgresql",
  host:    "localhost",
  database: "app_development",
  username: "postgres",
  password: "secret",
  pool:    10,
  checkout_timeout: 5
)
```

Полезные методы:

```ruby
pool = ActiveRecord::Base.connection_pool

pool.stat
# => { size: 5, connections: 1, busy: 0, dead: 0, idle: 1, waiting: 0, checkout_timeout: 5.0 }

pool.connections.size  # число открытых соединений в пуле
pool.active_connection? # есть ли соединение у текущего потока
```

В многопоточном скрипте (например, с `parallel` gem) каждый поток должен получать соединение из пула. Не передавайте объект `connection` между потоками — это приведёт к ошибкам.

При исчерпании пула ActiveRecord ждёт `checkout_timeout` секунд и бросает `ActiveRecord::ConnectionTimeoutError`.

## Закрытие соединений

В длинно живущих процессах важно освобождать соединения. В коротких скриптах ОС закроет их при завершении процесса, но явное закрытие — хорошая практика.

Вернуть соединение в пул после использования в текущем потоке:

```ruby
ActiveRecord::Base.connection_pool.release_connection
```

Закрыть все соединения пула:

```ruby
ActiveRecord::Base.connection_pool.disconnect!
```

Типичный шаблон для скрипта:

```ruby
require "active_record"

ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL"))

begin
  User.where(active: true).each { |u| puts u.email }
  User.create!(email: "new@example.com", name: "New User")
ensure
  ActiveRecord::Base.connection_pool.disconnect!
end
```

В веб-приложениях на Puma/Unicorn пул живёт весь жизненный цикл воркера. В Sidekiq-джобах соединение автоматически возвращается в пул после выполнения задачи, если middleware настроен корректно.

## Выводы

ActiveRecord без Rails — практичный инструмент для скриптов и утилит, которым нужен объектный доступ к PostgreSQL. Минимальная настройка сводится к `establish_connection` и объявлению модели.

Ключевые моменты:

- `activerecord` + `pg` — достаточно для работы с PostgreSQL.
- `establish_connection` создаёт пул соединений, общий для наследников `ActiveRecord::Base`.
- Схему можно исследовать через `columns`, `table_exists?` и `connection`.
- Для массовых операций предпочитайте `insert_all` / `upsert_all` вместо тысяч `create!`.
- Управляйте пулом явно в скриптах: `disconnect!` в `ensure`-блоке.
- Для простых разовых запросов чистый SQL или `psql` могут быть быстрее и прозрачнее.

Полный минимальный скрипт:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "active_record"

class User < ActiveRecord::Base
end

ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL"))

begin
  puts "Active users: #{User.where(active: true).count}"

  user = User.find_or_create_by!(email: "script@example.com") do |u|
    u.name = "Script User"
    u.active = true
  end

  puts "Created/found user ##{user.id}: #{user.email}"
ensure
  ActiveRecord::Base.connection_pool.disconnect!
end
```

Запуск:

```bash
DATABASE_URL="postgresql://postgres:secret@localhost:5432/app_development" ruby script.rb
```
