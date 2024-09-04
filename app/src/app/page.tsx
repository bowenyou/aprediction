import React from "react";

import BetBlock from "@/components/BetBlock";

const HomePage = () => {
  return (
    <main className="p-4">
      <h1>Aptos Prediction Game</h1>
      <div className="flex flex-wrap">
        <BetBlock state="expired" gameNumber={1234} currentPrice={505.2456} />
        <BetBlock state="live" gameNumber={1234} currentPrice={505.2456} lockedPrice={505.2456} />
        <BetBlock state="next" gameNumber={1234} />
        <BetBlock state="later" gameNumber={1234} />
      </div>
    </main>
  );
};

export default HomePage;
