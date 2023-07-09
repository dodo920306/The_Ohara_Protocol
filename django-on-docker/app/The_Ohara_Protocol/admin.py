from django.contrib import admin
from .models import Book, User, Key, Sale

# Register your models here.
admin.site.register(Book)
admin.site.register(Key)
admin.site.register(Sale)
