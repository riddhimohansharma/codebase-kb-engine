const express = require("express");
const { Kafka } = require("kafkajs");
const app = express();
const kafka = new Kafka({ brokers: [process.env.KAFKA_BROKERS] });
app.get("/health", (req, res) => res.send("ok"));
app.post("/checkout", async (req, res) => {
  await kafka.producer().send({ topic: "orders.created", messages: [{ value: "x" }] });
  res.status(202).end();
});
app.listen(3000);
