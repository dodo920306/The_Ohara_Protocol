# Ohara Protocol
![image](https://user-images.githubusercontent.com/74814435/233918652-b6a1d795-b995-4742-8fb5-4e343dccbafa.png)

## Overview
 This repository contains the source code of the Ohara Protocol, an E-Book trading system based on the ERC-1155 standard running on the Arbitrum blockchain.

 It allows publishers to mint their E-Books as NFTs and sell them to buyers. The system utilizes the Arbitrum chain for its high throughput and low transaction fees, providing a seamless and efficient E-Book trading experience for all parties involved.
 
 You can see more details on https://100.adi.gov.tw/ahvs1?id=62.
 
 This project is still under development, and we welcome any suggestions for improvement. You can help us identify issues by using the "Issues" tab above. Your feedback is valuable and we appreciate your contribution to the project's development.

## Prerequisites
You should have well functional truffle, docker, and docker-compose installed on your computer.

## Installation
 Please clone this repository and run
 ```bash
 $ npm install
 ```
 under the project root directory.

 Then, put the MNEMONIC and INFURA_KEY into the `.env` file

 ```
 MNEMONIC = "..."
 INFURA_KEY = "..."
 ```
 
 Now, you can use truffle to develop and test this project.

 You can choose the migration you want from migrationslib and copy it to the migrations file.

 For example, you can copy migrationslib/1_deploy.js to the migrations file, and use

 ```bash
 $ npx truffle migrate --network goerli
 ```
 
 to upload the contract and proxy on chain.

 Then, config django-on-docker/.env.dev, .env.prod, and .env.prod.db according to the samples and what your need.

 Finally, use

 ```bash
 $ cd django-on-docker && docker-compose up -d --build
 ```

 to run the server.

 You should see the website on your port 80 now.
