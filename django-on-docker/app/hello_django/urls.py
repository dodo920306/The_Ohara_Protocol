"""hello_django URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/3.2/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static


from The_Ohara_Protocol import views

urlpatterns = [
    path("grantPublisherByDefaultAdmin/", views.grantPublisherByDefaultAdmin, name='grantPublisherByDefaultAdmin'),
    path("setIdToPublisherByDefaultAdmin/", views.setIdToPublisherByDefaultAdmin, name='setIdToPublisherByDefaultAdmin'),
    path("grantPublisher/", views.grantPublisher, name='grantPublisher'),
    path("setIdToPublisher/", views.setIdToPublisher),
    path("mint/", views.mint, name='mint'),
    path("balanceOf/", views.balanceOf),
    path("admin/", admin.site.urls),
    path("", views.mainPage, name='main'),
    path("myPublisher/", views.publisherPage, name="publisher"),
    path("afterPublisher/", views.afterPublisherPage),
    path("registerPublisher/", views.registerPublisherPage, name="registerPublisher"),
    path("publish/", views.publishPage, name="publish"),
    path('metadata/<str:hex_string>.json', views.metadata, name='metadata'),
    path('read/', views.readBook, name='readBook'),
    path('accounts/', include('allauth.urls')),
    path('accounts/register/', views.register, name='register'),
]

if bool(settings.DEBUG):
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
