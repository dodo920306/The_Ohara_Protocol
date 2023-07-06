from django.db import models
from django.contrib.auth.models import User


# Create your models here.
class Book(models.Model):
    name = models.CharField(max_length=100)
    author = models.CharField(max_length=100)
    publisher = models.CharField(max_length=100)
    category = models.CharField(max_length=100)
    price = models.DecimalField(max_digits=10, decimal_places=2)
    amount = models.IntegerField()
    profit = models.DecimalField(max_digits=5, decimal_places=2)
    url = models.URLField(blank=True)
    intro = models.TextField(blank=True, null=True)
    cover = models.ImageField(upload_to='')
    chosen1 = models.ImageField(upload_to='', blank=True)
    chosen2 = models.ImageField(upload_to='', blank=True)
    chosen3 = models.ImageField(upload_to='', blank=True)
    chosen4 = models.ImageField(upload_to='', blank=True)
    book_file = models.FileField(upload_to='')
    Arweave = models.CharField(max_length=65)

    def __str__(self):
        return self.name


class Key(models.Model):
    key = models.BinaryField(max_length=16)

    def __str__(self):
        return self.id
