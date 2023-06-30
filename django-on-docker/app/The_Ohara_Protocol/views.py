from django.shortcuts import render
from django.http import JsonResponse, HttpResponseRedirect
from web3 import Web3
import os
from .models import Book
from uuid import uuid4
from django.core import serializers
from django.conf import settings
from arweave.arweave_lib import Wallet, Transaction
from arweave.transaction_uploader import get_uploader
import json
from .forms import BookForm


f = open("/home/app/web/ohara.json")
data = json.load(f)
abi = data["abi"]
w3 = Web3(Web3.HTTPProvider("https://arbitrum-goerli.infura.io/v3/" + os.environ.get("INFURA_KEY")))
contract = w3.eth.contract(address='0xDaB5e5bB35B3705338Ad5082930D562aD864E239', abi=abi)
f.close()


def sendTx(function_name, *args):
    func = getattr(contract.functions, function_name)

    tx = func(*args).build_transaction({
        'from': '0x515C81D96ad5291Db9825feb6DdAd6D9746e9306',
        'chainId': 421613,
        'gas': func(*args).estimate_gas({'from': '0x515C81D96ad5291Db9825feb6DdAd6D9746e9306'}) + 10000,
        'nonce': w3.eth.get_transaction_count('0x515C81D96ad5291Db9825feb6DdAd6D9746e9306'),
    })
    signed_tx = w3.eth.account.sign_transaction(tx, os.environ.get("PRIVATE_KEY"))
    tx_hash = w3.eth.send_raw_transaction(signed_tx.rawTransaction)

    return w3.eth.wait_for_transaction_receipt(tx_hash)


def callTx(function_name, *args):
    func = getattr(contract.caller, function_name)
    return func(*args)


def grantPublisherByDefaultAdmin(request):
    publisher = request.GET.get('publisher')
    account = request.GET.get('account')
    dict_attr = dict(sendTx("grantPublisher", publisher, account))
    dict_attr['blockHash'] = dict_attr['blockHash'].hex()
    dict_attr['transactionHash'] = dict_attr['transactionHash'].hex()
    dict_attr['logsBloom'] = dict_attr['logsBloom'].hex()
    dict_attr['logs'] = [dict(topic) for topic in dict_attr['logs']]
    for item in dict_attr['logs']:
        item['topics'] = [topic.hex() for topic in item['topics']]
        item['data'] = item['data'].hex()
        item['transactionHash'] = item['transactionHash'].hex()
        item['blockHash'] = item['blockHash'].hex()

    return JsonResponse(dict_attr)


def setIdToPublisherByDefaultAdmin(request):
    id = request.GET.get('id')
    publisher = request.GET.get('publisher')
    dict_attr = dict(sendTx("setIdToPublisher", int(id), publisher))
    dict_attr['blockHash'] = dict_attr['blockHash'].hex()
    dict_attr['transactionHash'] = dict_attr['transactionHash'].hex()
    dict_attr['logsBloom'] = dict_attr['logsBloom'].hex()
    dict_attr['logs'] = [dict(topic) for topic in dict_attr['logs']]
    for item in dict_attr['logs']:
        item['topics'] = [topic.hex() for topic in item['topics']]
        item['data'] = item['data'].hex()
        item['transactionHash'] = item['transactionHash'].hex()
        item['blockHash'] = item['blockHash'].hex()
    return JsonResponse(dict_attr)


def grantPublisher(request):
    publisher = request.GET.get('publisher')
    account = request.GET.get('account')
    return render(request, "grantPublisher.html", {
        "publisher": publisher,
        "account": account,
    })


def setIdToPublisher(request):
    id = request.GET.get('id')
    publisher = request.GET.get('publisher')
    return render(request, "setIdToPublisher.html", {
        "id": id,
        "publisher": publisher,
    })


def mint(request):
    account = request.GET.get('account')
    id = request.GET.get('id')
    amount = request.GET.get('amount')
    return render(request, "mint.html", {
        "account": account,
        "id": id,
        "amount": amount,
    })


def balanceOf(request):
    account = request.GET.get('account')
    id = request.GET.get('id')
    return render(request, "balanceOf.html", {
        "account": account,
        "id": id,
    })


def mainPage(request):
    if request.method == "POST":
        id = request.POST.get("id")
        try:
            book = Book.objects.get(id=id)
            json_data = {
                'id': book.id,
                "name": book.name,
                "author": book.author,
                "publisher": book.publisher,
                "category": book.category,
                "price": str(book.price),
                "amount": book.amount,
                "profit": str(book.profit),
                "url": book.url,
                "intro": book.intro,
                "cover": book.cover.url,
                "chosen1": book.chosen1.url if book.chosen1 else "",
                "chosen2": book.chosen2.url if book.chosen2 else "",
                "chosen3": book.chosen3.url if book.chosen3 else "",
                "chosen4": book.chosen4.url if book.chosen4 else "",
                "book_file": book.book_file.url,
                "Arweave": book.Arweave
            }
            return JsonResponse(json_data)
        except Book.DoesNotExist:
            return JsonResponse({"detail": "The book doesn't exist."})
    else:
        return render(request, "main.html", {'value': callTx("currentId")})


def publisherPage(request):
    return render(request, "publisher.html")


def afterPublisherPage(request):
    referer = request.META.get('HTTP_REFERER')
    if referer and referer.startswith(request.build_absolute_uri('/')[:-1]):
        if request.method == "POST":
            try:
                id = request.POST.get('id')
                book = Book.objects.get(id=id)
                book.intro = request.POST.get('intro')
                book.category = request.POST.get('category')
                if request.FILES.get('chosen1'):
                    if book.chosen1:
                        file_path = os.path.join(settings.MEDIA_ROOT, book.chosen1.name)
                        os.remove(file_path)
                    book.chosen1 = request.FILES.get('chosen1')
                    book.chosen1.name = uuid4().hex
                if request.FILES.get('chosen2'):
                    if book.chosen2:
                        file_path = os.path.join(settings.MEDIA_ROOT, book.chosen2.name)
                        os.remove(file_path)
                    book.chosen2 = request.FILES.get('chosen2')
                    book.chosen2.name = uuid4().hex
                if request.FILES.get('chosen3'):
                    if book.chosen3:
                        file_path = os.path.join(settings.MEDIA_ROOT, book.chosen3.name)
                        os.remove(file_path)
                    book.chosen3 = request.FILES.get('chosen3')
                    book.chosen3.name = uuid4().hex
                if request.FILES.get('chosen4'):
                    if book.chosen4:
                        file_path = os.path.join(settings.MEDIA_ROOT, book.chosen4.name)
                        os.remove(file_path)
                    book.chosen4 = request.FILES.get('chosen4')
                    book.chosen4.name = uuid4().hex
                book.save()
                return JsonResponse({"detail": "success"})
            except Book.DoesNotExist:
                return JsonResponse({"detail": "fail"})
        else:
            name = request.GET.get('name')
            hash = request.GET.get('hash')
            return render(request, "afterPublisher.html", {
                "name": name,
                "hash": hash,
                'value': callTx("currentId")
            })
    return HttpResponseRedirect("/myPublisher/")


def registerPublisherPage(request):
    return render(request, "registerPublisher.html")


def publishPage(request):
    referer = request.META.get('HTTP_REFERER')
    if referer and referer.startswith(request.build_absolute_uri('/')[:-1]):
        if request.method == "POST":
            id = request.POST.get("id")
            form = BookForm(request.POST, request.FILES)
            if form.is_valid():
                book = form.save(commit=False)
                book.id = id
                book.cover.name = uuid4().hex
                book.book_file.name = uuid4().hex
                if book.chosen1:
                    book.chosen1.name = uuid4().hex
                if book.chosen2:
                    book.chosen2.name = uuid4().hex
                if book.chosen3:
                    book.chosen3.name = uuid4().hex
                if book.chosen4:
                    book.chosen4.name = uuid4().hex

                wallet = Wallet("/home/app/web/arweave.json")
                form_data = form.cleaned_data
                form_data["id"] = book.id
                form_data["price"] = str(form_data["price"])
                form_data["profit"] = str(form_data["profit"])
                exclude_fields = ['category', 'intro', 'cover', 'chosen1', 'chosen2', 'chosen3', 'chosen4', 'book_file']
                for exclude_field in exclude_fields:
                    form_data.pop(exclude_field, None)

                with book.book_file.open(mode='r') as mypdf:
                    pdf_string_data = mypdf.read()

                    transaction = Transaction(wallet, data=pdf_string_data)
                    transaction.add_tag('Content-Type', 'application/pdf')
                    transaction.sign()
                    transaction.send()
                    form_data['book_file'] = "https://arweave.net/" + transaction.id

                    json_data = json.dumps(form_data, indent=4)
                    transaction = Transaction(wallet, data=json_data)
                    transaction.add_tag('Content-Type', 'application/json')
                    transaction.sign()
                    transaction.send()

                    book.Arweave = "https://arweave.net/" + transaction.id
                    book.save()

                return JsonResponse({"detail": "success"})
            else:
                return JsonResponse({"detail": "fail"})
        else:
            name = request.GET.get('name')
            form = BookForm()
            return render(request, "publish.html", {
                "name": name,
                'form': form
            })
    return HttpResponseRedirect("/myPublisher/")


def metadata(request, hex_string):
    id = int(hex_string, 16)
    try:
        book = Book.objects.get(id=id)
        return HttpResponseRedirect(book.Arweave)
    except Book.DoesNotExist:
        return JsonResponse({"detail": "Not found"})
