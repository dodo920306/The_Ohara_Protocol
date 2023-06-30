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
from django.urls import path
from django.conf import settings
from django.conf.urls.static import static


from The_Ohara_Protocol.views import grantPublisher, setIdToPublisher, grantPublisherByDefaultAdmin, setIdToPublisherByDefaultAdmin, mint, balanceOf, mainPage, publisherPage, afterPublisherPage, registerPublisherPage, publishPage, metadata

urlpatterns = [
    path("grantPublisherByDefaultAdmin/", grantPublisherByDefaultAdmin, name='grantPublisherByDefaultAdmin'),
    path("setIdToPublisherByDefaultAdmin/", setIdToPublisherByDefaultAdmin, name='setIdToPublisherByDefaultAdmin'),
    path("grantPublisher/", grantPublisher, name='grantPublisher'),
    path("setIdToPublisher/", setIdToPublisher),
    path("mint/", mint, name='mint'),
    path("balanceOf/", balanceOf),
    path("admin/", admin.site.urls),
    path("", mainPage, name='main'),
    path("myPublisher/", publisherPage, name="publisher"),
    path("afterPublisher/", afterPublisherPage),
    path("registerPublisher/", registerPublisherPage, name="registerPublisher"),
    path("publish/", publishPage, name="publish"),
    path('metadata/<str:hex_string>.json', metadata, name='metadata')
]

if bool(settings.DEBUG):
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
