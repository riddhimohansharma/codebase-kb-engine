package com.acme.orders;

import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/orders")
public class OrderController {
  @GetMapping("/{id}")
  public Order get(@PathVariable long id) { return null; }

  @PostMapping
  public Order create(@RequestBody Order o) { return o; }
}
