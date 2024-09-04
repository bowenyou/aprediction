"use client";

import React from "react";
import { PetraWallet } from "petra-plugin-wallet-adapter";
import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react";
import { WalletSelector } from "@aptos-labs/wallet-adapter-ant-design";
import "@aptos-labs/wallet-adapter-ant-design/dist/index.css";

import BetBlock from "@/components/BetBlock";

const wallets = [new PetraWallet()];

const HomePage = () => {
  return (
    <AptosWalletAdapterProvider plugins={wallets} autoConnect={true}>
      <main className="p-4">
        <h1>Aptos Prediction Game</h1>
        <div className="flex flex-wrap">
          <BetBlock state="expired" gameNumber={1234} currentPrice={505.2456} />
          <BetBlock
            state="live"
            gameNumber={1234}
            currentPrice={505.2456}
            lockedPrice={505.2456}
          />
          <BetBlock state="next" gameNumber={1234} />
          <BetBlock state="later" gameNumber={1234} />
          <WalletSelector />
        </div>
      </main>
    </AptosWalletAdapterProvider>
  );
};

export default HomePage;
