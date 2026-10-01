from django.urls import path
from . import views

urlpatterns = [
    path("products/<int:pk>/", views.product_detail),
]
