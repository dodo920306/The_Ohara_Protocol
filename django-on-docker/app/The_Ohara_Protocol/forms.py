from django import forms
from .models import Book


class BookForm(forms.ModelForm):
    class Meta:
        model = Book
        exclude = ['Arweave']
        widgets = {
            'intro': forms.Textarea(attrs={'rows': 4}),
        }
