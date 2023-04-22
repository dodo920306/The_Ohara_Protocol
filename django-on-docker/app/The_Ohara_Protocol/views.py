from django.shortcuts import render

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