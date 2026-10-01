package com.acme.orders;

import jakarta.persistence.*;

@Entity
@Table(name = "orders")
public class Order {
  @Id Long id;
}
