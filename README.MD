# TgRabbit

Микросервисная система на **Nest.js** с **RabbitMQ** и **Telegram Bot API**.

Producer принимает HTTP-запросы и публикует события в очередь. Consumer читает сообщения, обеспечивает идемпотентность и делегирует отправку Notifier. Notifier доставляет уведомления в Telegram.

```
HTTP Client → Producer (:3000) → RabbitMQ → Consumer → Notifier (:3001) → Telegram
```

---

## Требования

- **Node.js** 20+ и **npm** 10+ — для локальной разработки и тестов
- **Docker** и **Docker Compose** v2 — для RabbitMQ и полного стека в контейнерах

---

## Запуск через Docker Compose

Поднимает **весь pipeline** в контейнерах: RabbitMQ, Producer, Consumer, Notifier.

### Подготовка

```bash
git clone git@github.com:ilmerianin/TgRabbit.git
cd TgRabbit

cp .env.example .env
```

В `.env` обязательно задайте:

| Переменная | Для Docker Compose |
|------------|-------------------|
| `TELEGRAM_BOT_TOKEN` | Токен от бота телеграмм|
| `RABBITMQ_QUEUE` | Обычно `events.notifications` (можно не менять) |



### Запуск стека

Из **корня репозитория** (где лежит `docker-compose.yml`):

```bash
# Сборка образов и запуск в foreground (логи в терминале)
docker compose up --build

# Или в фоне
docker compose up --build -d
```

Эквивалент через npm:

```bash
npm run docker:up
```

### Порядок старта сервисов

1. **rabbitmq** — ждёт `healthcheck` (ping)
2. **notifier** — ждёт `/health` (токен задан)
3. **producer** — после healthy RabbitMQ
4. **consumer** — после healthy RabbitMQ и Notifier

Consumer вызывает Notifier по внутреннему URL `http://notifier:3001` (не `localhost`).

### Полезные команды

```bash
# Статус контейнеров
docker compose ps

# Логи всех сервисов или одного
docker compose logs -f
docker compose logs -f consumer

# Остановка
docker compose down

# Пересборка без кэша (после смены кода)
docker compose build --no-cache
docker compose up -d
```

### Проверка после старта

Health:

```bash
curl http://localhost:3000/health   # producer + rabbitmq
curl http://localhost:3001/health   # notifier + telegram token
```

Публикация события (замените `YOUR_CHAT_ID`):

```bash
curl -X POST http://localhost:3000/events \
  -H 'Content-Type: application/json' \
  -d '{"payload":{"chatId":"YOUR_CHAT_ID","text":"Hello from TgRabbit"}}'
```

Ожидаемый ответ: `{"id":"<uuid>","status":"published"}`. Сообщение должно прийти в Telegram с префиксом `[TgRabbit]`.

Smoke-тест с хоста (сервисы уже слушают localhost):

```bash
CHAT_ID=YOUR_CHAT_ID npm run smoke-test
```

RabbitMQ Management UI: http://localhost:15672 (логин `guest` / `guest`).

### Только RabbitMQ (для локальной разработки без полного стека)

```bash
npm run docker:rabbitmq
# или: docker compose up -d rabbitmq
```

Далее запускайте Producer / Consumer / Notifier через `npm run start:*` (см. раздел ниже).

### Troubleshooting (Docker)

| Проблема | Что сделать |
|----------|-------------|
| Consumer не стартует | Проверьте `docker compose ps` — notifier и rabbitmq должны быть `healthy` |
| `503` на `/health` producer | RabbitMQ ещё не готов; подождите или `docker compose logs rabbitmq` |
| `503` на `/health` notifier | Нет или неверный `TELEGRAM_BOT_TOKEN` в `.env` |
| `PRECONDITION_FAILED` на очереди | Старая топология в RabbitMQ: `docker compose exec rabbitmq rabbitmqctl delete_queue events.notifications` (при необходимости и DLQ) |
| Нет сообщения в Telegram | Проверьте токен, `chatId`, логи: `docker compose logs notifier consumer` |
| Блокировка Telegram API | В `.env` задайте `TELEGRAM_API_BASE_URL` (локальный Bot API server) |

---

## Быстрый старт (кратко)

```bash
cp .env.example .env   # TELEGRAM_BOT_TOKEN
docker compose up --build
curl http://localhost:3000/health
curl -X POST http://localhost:3000/events -H 'Content-Type: application/json' \
  -d '{"payload":{"chatId":"YOUR_CHAT_ID","text":"Hello"}}'
```

---

## Локальная разработка

### 1. Зависимости

```bash
npm run install:deps
# или: cd nest-microservices && npm install
```

### 2. RabbitMQ

```bash
npm run docker:rabbitmq
# Management UI: http://localhost:15672 (guest / guest)
```

### 3. Переменные окружения

Скопируйте `.env.example` → `.env` в корень репозитория.

| Переменная | Локально |
|------------|----------|
| `RABBITMQ_URL` | `amqp://guest:guest@localhost:5672` |
| `RABBITMQ_QUEUE` | `events.notifications` |
| `TELEGRAM_BOT_TOKEN` | Токен бота |
| `NOTIFIER_URL` | `http://localhost:3001` (для Consumer) |
| `PORT` | HTTP-порт (Producer: 3000, Notifier: 3001, Consumer: 3002) |

### 4. Запуск сервисов (3 терминала)

```bash
npm run start:notifier   # :3001
npm run start:consumer   # :3002, RabbitMQ consumer
npm run start:producer   # :3000
```

### 5. Пример запроса

```bash
curl -X POST http://localhost:3000/events \
  -H 'Content-Type: application/json' \
  -d '{"payload":{"chatId":"123456789","text":"Hello via pipeline"}}'
```

Прямой вызов Notifier (без очереди):

```bash
curl -X POST http://localhost:3001/notify \
  -H 'Content-Type: application/json' \
  -d '{"chatId":"123456789","text":"Direct notify"}'
```

---

## Swagger

| Сервис | URL |
|--------|-----|
| Producer | http://localhost:3000/api |
| Notifier | http://localhost:3001/api |

Consumer — фоновый worker без публичного API (кроме `/health` на :3002 для Docker).

---

## API

### Producer

| Метод | Путь | Описание |
|-------|------|----------|
| `GET` | `/health` | RabbitMQ connection |
| `POST` | `/events` | Опубликовать событие уведомления |

**POST /events** — тело запроса:

```json
{
  "payload": {
    "chatId": "123456789",
    "text": "Текст уведомления"
  }
}
```

**Ответ:**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "published"
}
```

### Notifier

| Метод | Путь | Описание |
|-------|------|----------|
| `GET` | `/health` | Bot token configured |
| `POST` | `/notify` | Отправить сообщение в Telegram |

Формат сообщения в Telegram: `[TgRabbit]\n{text}`

---

## Тесты

```bash
npm test              # unit-тесты
npm run test:e2e      # e2e (Producer, Notifier, Consumer, pipeline)
```

Из каталога `nest-microservices`:

```bash
npm run test:cov      # покрытие
```

Pipeline e2e (`test/pipeline.e2e-spec.ts`) проверяет цепочку **Producer → EventDto → Consumer → mock Notifier** без RabbitMQ и Telegram.

---

## Структура репозитория

```
TgRabbit/
├── docker-compose.yml
├── .env.example
├── scripts/smoke-test.sh
├── docs/                    # PROJECT_CONTEXT, этапы, SOLID-review
└── nest-microservices/      # Nest.js monorepo
    ├── apps/
    │   ├── producer/        # HTTP → RabbitMQ
    │   ├── consumer/        # RabbitMQ → Notifier
    │   └── notifier/        # HTTP → Telegram
    └── libs/
        ├── contracts/       # @app/contracts — DTO, interfaces, tokens
        ├── rabbitmq/        # @app/rabbitmq — AMQP topology
        └── common/          # @app/common — facade re-export
```

---

## Порты

| Сервис        | Порт        | Публикуется |
|--------       |------       |-------------|
| Producer      | 3000        | да |
| Notifier      | 3001        | да |
| Consumer      | 3002        | нет (health internal) |
| RabbitMQ AMQP | 5672        | да |
| RabbitMQ Management | 15672 | да |

---

