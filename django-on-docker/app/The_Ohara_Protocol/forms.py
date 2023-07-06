from django import forms
from .models import Book
from django.contrib.auth.forms import UserCreationForm


class BookForm(forms.ModelForm):
    class Meta:
        model = Book
        exclude = ['Arweave']
        widgets = {
            'intro': forms.Textarea(attrs={'rows': 4}),
        }
