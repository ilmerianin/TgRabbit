# TgRabbit

Микросервисная система на **Nest.js** с **RabbitMQ** и **Telegram Bot API**.

Producer принимает HTTP-запросы и публикует события в очередь. Consumer читает сообщения, обеспечивает идемпотентность и делегирует отправку Notifier. Notifier доставляет уведомления в Telegram.

```
HTTP Client → Producer (:3000) → RabbitMQ → Consumer → Notifier (:3001) → Telegram
```

---

## 

- **Node.js** 20+
- **npm** 10+
- **Docker** и **Docker Compose** (для RabbitMQ и полного стека)

---

## Быстрый старт (Docker)

```bash
git clone <repository-url>
cd TgRabbit

cp .env.example .env
# Заполните TELEGRAM_BOT_TOKEN 

docker compose up --build
```

Проверка:

```bash
curl http://localhost:3000/health
curl http://localhost:3001/health

curl -X POST http://localhost:3000/events \
  -H 'Content-Type: application/json' \
  -d '{"payload":{"chatId":"YOUR_CHAT_ID","text":"Hello from TgRabbit"}}'
```

Smoke-тест:

```bash
CHAT_ID=YOUR_CHAT_ID npm run smoke-test
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

 `RABBITMQ_URL`- `amqp://guest:guest@localhost:5672` 
 `RABBITMQ_QUEUE` - `events.notifications` 
 `TELEGRAM_BOT_TOKEN` -Токен бота 
 `NOTIFIER_URL` -`http://localhost:3001` (для Consumer) 
 `PORT`  - HTTP-порт (Producer: 3000, Notifier: 3001, Consumer: 3002) 

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

