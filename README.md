# Smart Public Ticketing System

A fast and scalable transport management system built with Ballerina that helps run modern city transit services. It manages passenger registration, ticket processing, real time notifications, and seat availability across multiple connected services.

---

## System Architecture


The system uses a combination of communication methods to keep the system fast and efficient. It uses REST APIs for instant actions like user registration, and Kafka event messaging for background tasks such as updating seat availability and sending notifications.

### The Microservices

#### 1. [Passenger Service](passenger-service) (`Port 9010`)
- **Responsibilities**: Handles secure registration, login, and profile management.
- **Event Consumer**: Listens for `ticket.purchased` events to maintain a local, high-speed cache of a passenger's tickets in MongoDB.
- **Key Feature**: Decoupled from the Ticketing service to ensure user profiles are accessible even if the ticketing engine is under heavy load.

#### 2. [Ticketing Service](ticketing-service) (`Port 9003`)
- **Responsibilities**: Manages the lifecycle of a ticket: `CREATED` → `PAID` → `VALIDATED`.
- **State Machine**: Enforces strict rules, tickets cannot be validated unless they have been marked as `PAID`.
- **Event Producer**: Publishes `ticket.purchased` and `ticket.validations` events to drive the rest of the system.

#### 3. [Payment Service](payment-service) (`Port 8084`)
- **Responsibilities**: Simulates secure transaction processing.
- **Concurrency Control**: Implements **Atomic Status Updates** in MongoDB to prevent double-refunds or race conditions during high-volume periods.
- **Standardization**: Uses a unified `KAFKAHOST` configuration to ensure zero-config connectivity in containerized environments.

#### 4. [Notification Service](notification-service) (`Port 9011`)
- **Responsibilities**: A reactive service that monitors multiple Kafka topics.
- **Capabilities**: 
  - **Payment Alerts**: Notifies users of successful or failed transactions.
  - **Schedule Updates**: Broadcasts delays or cancellations to all affected passengers.
  - **Validation Receipts**: Confirms successful boarding.
- **Output**: Simulates multi-channel delivery via structured console logging.

#### 5. [Transport Service](transport-service) (`Port 9002`)
- **Responsibilities**: Manages Routes, Vehicles, and Trips.
- **Inventory Logic**: Automatically decrements available seats on a specific `tripId` when a ticket purchase is confirmed via Kafka.
- **Dual Interface**: Offers both a REST API for the Admin service and a Console CLI for terminal-based management.

#### 6. [Admin Service](admin-service) (`Port 9006`)
- **Responsibilities**: collects data from the Transport and Payment services.
- **Reports**: Generates Traffic occupancy reports and Sales revenue analytics.
- **Resilience**: Uses a centralized HTTP client configuration with configurable retry logic for inter-service calls.

#### 7. System Orchestration (`docker-compose.yml`)
- **Infrastructure**: Starts up **MongoDB 7.0**, **Confluent Kafka 7.5.0**, and **Zookeeper**.
- **Networking**: Creates a dedicated `transport-network` to allow services to communicate using container names.
- **Persistence**: Uses Docker volumes to ensure your data stays safe even if containers are restarted.
- **Performance**: Implements a shared `ballerina-cache` volume across all services to drastically reduce compilation times during development.

---

## Tech Stack & Infrastructure

| Component | Technology | Role |
| :--- | :--- | :--- |
| **Language** | Ballerina 2201.12.10 | Cloud-native programming & integration |
| **Runtime** | Docker | Containerization & Orchestration |
| **Database** | MongoDB 7.0 | Document storage for high-availability |
| **Messaging** | Confluent Kafka 7.5.0 | High-throughput event streaming |
| **API** | REST / JSON | Service-to-service communication |

---

## Deployment & Testing

### 1. Startup
Spin up the entire infrastructure (Zookeeper, Kafka, MongoDB) and all 6 services with a single command:
```
docker compose up --build
```

### 2. The Test Flow
To verify the entire system is healthy, perform this end-to-end flow in Postman:

1.  **Register**: `POST :9010/passenger/register`
2.  **Request Ticket**: `POST :9003/ticketing/request` (Status starts as `CREATED`)
3.  **Process Payment**: `POST :8084/payments`
    - *Check Logs*: `notification-service` should alert the user.
    - *Check Database*: `transport-service` should show 1 less seat available.
    - *Check Profile*: `passenger-service` should now show the ticket as `PAID`.
4.  **Validate Boarding**: `POST :9003/ticketing/validate/{id}`
    - *Check Logs*: `notification-service` should confirm the passenger is boarded.

---
*Developed as a Project for DSA612S*