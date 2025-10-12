FROM ballerina/ballerina:latest

WORKDIR /app

COPY . .

RUN bal build

EXPOSE 9002

CMD ["bal", "run"]
