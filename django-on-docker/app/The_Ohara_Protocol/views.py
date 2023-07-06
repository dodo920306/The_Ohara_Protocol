from django.shortcuts import render
from django.http import JsonResponse, HttpResponseRedirect, FileResponse, HttpResponse
from web3 import Web3
import os
from .models import Book, Key
from uuid import uuid4
from django.core import serializers
from django.conf import settings
from arweave.arweave_lib import Wallet, Transaction
from arweave.transaction_uploader import get_uploader
import json
from .forms import BookForm, UserCreationForm
from Crypto.Cipher import AES
from Crypto.Random import get_random_bytes
from tempfile import TemporaryFile
import logging
from django.contrib.auth.decorators import login_required


f = open("/home/app/web/ohara.json")
data = json.load(f)
abi = data["abi"]
address = data["networks"]["421613"]["address"]
w3 = Web3(Web3.HTTPProvider("https://arbitrum-goerli.infura.io/v3/" + os.environ.get("INFURA_KEY")))
contract = w3.eth.contract(address=address, abi=abi)
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


@login_required
def grantPublisher(request):
    publisher = request.GET.get('publisher')
    account = request.GET.get('account')
    return render(request, "grantPublisher.html", {
        "publisher": publisher,
        "account": account,
        'abi': json.dumps(abi),
        "address": address,
    })


@login_required
def setIdToPublisher(request):
    id = request.GET.get('id')
    publisher = request.GET.get('publisher')
    return render(request, "setIdToPublisher.html", {
        "id": id,
        "publisher": publisher,
        'abi': json.dumps(abi),
        'address': address,
    })


@login_required
def mint(request):
    account = request.GET.get('account')
    id = request.GET.get('id')
    amount = request.GET.get('amount')
    return render(request, "mint.html", {
        "account": account,
        "id": id,
        "amount": amount,
        'abi': json.dumps(abi),
        "address": address
    })


@login_required
def balanceOf(request):
    account = request.GET.get('account')
    id = request.GET.get('id')
    return render(request, "balanceOf.html", {
        "account": account,
        "id": id,
        'abi': json.dumps(abi),
        "address": address,
    })


@login_required
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
        return render(request, "main.html", {'value': callTx("currentId"), 'abi': json.dumps(abi), 'address': address})


@login_required
def publisherPage(request):
    return render(request, "publisher.html", {'abi': json.dumps(abi), 'address': address})


@login_required
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
                'value': callTx("currentId"),
                'abi': json.dumps(abi),
                'address': address,
            })
    return HttpResponseRedirect("/myPublisher/")


@login_required
def registerPublisherPage(request):
    return render(request, "registerPublisher.html")


@login_required
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

                # <AES>
                iv = os.urandom(16)  # 包含16個隨機字節的初始化向量（IV），是在加密過程中用於增加隨機性和安全性的一個值。
                key = get_random_bytes(16)  # 包含16個隨機字節的金鑰，用於加密和解密過程。
                key_record = Key(key=key)
                key_record.id = book.id
                key_record.save()
                # 重複機率小到可以忽略。

                encryptor = AES.new(key, AES.MODE_CBC, iv)  # Cipher Block Chaining
                # CBC 是 Cipher Block Chaining 的縮寫，表示使用加密過的前一個密文塊與當前要加密的明文塊進行運算。
                # 在 CBC 模式下，每個明文塊會先與前一個密文塊進行 XOR 運算，然後再進行 AES 加密。
                # 這樣做可以提高加密的安全性，因為每個明文塊的加密都依賴於前一個密文塊。
                # 在加密過程中，第一個明文塊會使用初始化向量（IV）進行 XOR 運算，以增加隨機性。
                # 後續的明文塊則使用前一個密文塊進行 XOR 運算。

                chunksize = 64 * 1024
                file_size = book.book_file.size

                with book.book_file.open(mode='rb') as infile:
                    encrypted_data = bytearray()
                    encrypted_data.extend(file_size.to_bytes(8, byteorder='big'))
                    encrypted_data.extend(iv)

                    while True:
                        chunk = infile.read(chunksize)
                        if len(chunk) == 0:
                            break
                        elif len(chunk) % 16 != 0:
                            chunk += b' ' * (16 - len(chunk) % 16)

                        encrypted_chunk = encryptor.encrypt(chunk)
                        encrypted_data.extend(encrypted_chunk)
                    book.save()
                # </AES>
                book = Book.objects.get(id=id)
                file_path = os.path.join(settings.MEDIA_ROOT, book.book_file.name)
                with book.book_file.open(mode='w') as mypdf:
                    mypdf.write(encrypted_data.hex())

                # <Arweave Book>
                with open(file_path, "rb", buffering=0) as file_handler:
                    transaction = Transaction(wallet, file_handler=file_handler, file_path=file_path)
                    transaction.add_tag('Content-Type', 'text/plain')
                    transaction.sign()
                    uploader = get_uploader(transaction, file_handler)

                    while not uploader.is_complete:
                        uploader.upload_chunk()

                        logging.info("{}% complete, {}/{}".format(
                            uploader.pct_complete, uploader.uploaded_chunks, uploader.total_chunks
                        ))
                    form_data['book_file'] = "https://arweave.net/" + transaction.id
                # </Arweave Book>

                # <Arweave Metadata>
                json_data = json.dumps(form_data, indent=4)
                transaction = Transaction(wallet, data=json_data)
                transaction.add_tag('Content-Type', 'application/json')
                transaction.sign()
                transaction.send()
                # </Arweave Metadata>

                # <Local Metadata>
                book = Book.objects.get(id=id)
                book.Arweave = "https://arweave.net/" + transaction.id
                book.save()
                # </Local Metadata>

                return JsonResponse({"detail": "success"})
            else:
                return JsonResponse({"detail": "fail"})
        else:
            name = request.GET.get('name')
            form = BookForm()
            return render(request, "publish.html", {
                "name": name,
                'form': form,
                'abi': json.dumps(abi),
                "address": address,
            })
    return HttpResponseRedirect("/myPublisher/")


@login_required
def metadata(request, hex_string):
    id = int(hex_string, 16)
    try:
        book = Book.objects.get(id=id)
        return HttpResponseRedirect(book.Arweave)
    except Book.DoesNotExist:
        return JsonResponse({"detail": "Not found"})


@login_required
def readBook(request):
    id = request.POST.get("id")
    book = Book.objects.get(id=id).book_file
    key = Key.objects.get(id=id).key
    chunksize = 64 * 1024
    with book.open(mode='r') as mypdf:
        encrypted_data = bytes.fromhex(mypdf.read())
        iv = encrypted_data[8:24]
        decryptor = AES.new(key, AES.MODE_CBC, iv)
        decrypted_data = bytearray()
        index = 24  # 從索引 24 開始，跳過文件大小和 IV
        while index < len(encrypted_data):
            chunk = encrypted_data[index:index + chunksize]
            decrypted_chunk = decryptor.decrypt(chunk)
            decrypted_data.extend(decrypted_chunk)
            index += chunksize

        padding_byte = b' '
        last_non_padding_index = decrypted_data.rfind(padding_byte) + 1  # 找到最後一個非填充字節的索引
        decrypted_data = decrypted_data[:last_non_padding_index]

    temp_file = TemporaryFile()
    temp_file.write(decrypted_data)
    temp_file.seek(0)
    response = FileResponse(temp_file, content_type='application/octet-stream')
    response['Content-Disposition'] = f"attachment; filename={book.name}"
    return response


def register(request):
    if request.method == 'POST':
        form = UserCreationForm(request.POST)
        if form.is_valid():
            user = form.save(commit=False)
            user.is_active = True
            user.save()
            return HttpResponse(f'註冊成功！你現在可以登入了！<br /><a href=http://{request.get_host()}>現在就登入！</a>')
    else:
        form = UserCreationForm()
    return render(request, 'registration/register.html', {'form': form})
