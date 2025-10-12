💳 Payment Service

Overview

The Payment Service handles all payment processing for ticket purchases. It integrates with payment gateways (simulated), manages payment records in MongoDB, and publishes payment events to Kafka for downstream services like notifications and ticketing.

- Port: 8084  
- Technology: Ballerina, MongoDB, Apache Kafka  
- Database: MongoDB (`transportdb.payments` collection)

🏗️ Architecture

Payment Flow



┌─────────────────────────────────────────────────────────┐
│              Payment Processing Flow                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Client Request                                         │
│       │                                                 │
│       ▼                                                 │
│  ┌─────────────────────┐                               │
│  │ Validate Request    │                               │
│  │ - ticketId exists   │                               │
│  │ - amount > 0        │                               │
│  └──────────┬──────────┘                               │
│             │                                           │
│             ▼                                           │
│  ┌─────────────────────┐                               │
│  │ Process Payment     │                               │
│  │ (Gateway Simulation)│                               │
│  └──────────┬──────────┘                               │
│             │                                           │
│       ┌─────┴─────┐                                    │
│       │           │                                    │
│    SUCCESS      FAILURE                                │
│       │           │                                    │
│       ▼           ▼                                    │
│  ┌─────────┐  ┌─────────┐                             │
│  │ CONFIRM │  │  FAIL   │                             │
│  │ Payment │  │ Payment │                             │
│  └────┬────┘  └────┬────┘                             │
│       │            │                                   │
│       ▼            ▼                                   │
│  Save to MongoDB                                       │
│       │                                                │
│       ▼                                                │
│  Publish to Kafka (payments.processed)                │
│       │                                                │
│       ▼                                                │
│  Update Ticket Status (if CONFIRMED)                  │
│       │                                                │
│       ▼                                                │
│  Return Response                                       │
│                                                        │
└─────────────────────────────────────────────────────────┘



📊 Code Structure

Data Models

Payment Record
```ballerina
type Payment record {|
    string _id;              // UUID
    string ticketId;         // Reference to ticket
    string passengerId;      // Reference to passenger
    decimal amount;          // Payment amount
    string method;           // CARD | MOBILE_MONEY | CASH
    string status;           // INITIATED | CONFIRMED | FAILED | REFUNDED
    string createdAt;        // ISO 8601 timestamp
    string? processedAt;     // Optional processed timestamp
|};
````

Payment Request

```ballerina
type CreatePaymentRequest record {|
    string ticketId;
    string passengerId;
    decimal amount;
    string method;
|};
```

Refund Request

```ballerina
type RefundRequest record {|
    string reason;
|};
```

💰 Payment Operations

1. Process Payment

* Endpoint: `POST /payments`
* Creates a payment record, simulates payment processing, saves to MongoDB, publishes a Kafka event, updates ticket status.

2. Get Payment Details

* Endpoint: `GET /payments/{paymentId}`
* Retrieves a single payment by ID.

3. Get Payments for Ticket

* Endpoint: `GET /payments/ticket/{ticketId}`
* Returns all payments for a ticket.

4. Process Refund

* Endpoint: `POST /payments/{paymentId}/refund`
* Refunds a confirmed payment, updates status in MongoDB, publishes Kafka refund event.

5. Get All Payments (Admin)

* Endpoint: `GET /payments/all`
* Returns all payments with statistics (total, confirmed, refunded, total revenue).

🎯 Kafka Integration

* Topic: `payments.processed`
* Event Trigger: Payment confirmed or refunded
* Consumers: Notification service, ticketing updates

**Sample Kafka Event:**

--- JSON
{
  "paymentId": "UUID",
  "ticketId": "UUID",
  "passengerId": "UUID",
  "amount": 50.00,
  "status": "CONFIRMED",
  "timestamp": "ISO-8601"
}

 🧪 Testing Examples

Process Payment

powershell
$paymentBody = @{
    ticketId = 'TICKET-UUID'
    passengerId = 'PASSENGER-UUID'
    amount = 50.00
    method = 'CARD'
} | ConvertTo-Json



 📊 API Endpoints

| Method | Endpoint                       | Description              | Auth  |
| ------ | ------------------------------ | ------------------------ | ----- |
| GET    | `/payments/health`             | Health check             | No    |
| POST   | `/payments`                    | Process payment          | Yes   |
| GET    | `/payments/{paymentId}`        | Get payment details      | Yes   |
| GET    | `/payments/ticket/{ticketId}`  | Get payments by ticket   | Yes   |
| POST   | `/payments/{paymentId}/refund` | Refund payment           | Admin |
| GET    | `/payments/all`                | Get all payments & stats | Admin |


🔐 Payment Status Flow

INITIATED ─────► CONFIRMED ─────► REFUNDED
    │
    └────► FAILED


💡 Business Rules

* Amount must be > 0
* Ticket must exist and be in `CREATED` status
* Payment method must be valid
* Only `CONFIRMED` payments can be refunded
* Successful payment updates ticket to `PAID`
* Publishes Kafka event only on successful payment
