"use client";

import clsx from "clsx";
import { IoPlayCircleOutline } from "react-icons/io5";
import { CiNoWaitingSign } from "react-icons/ci";
import { CiClock2 } from "react-icons/ci";
import { IoIosArrowUp } from "react-icons/io";
import { IoIosArrowDown } from "react-icons/io";
import { PiEquals } from "react-icons/pi";
import { useState } from "react";

type BetState = "live" | "expired" | "next" | "later";
interface HeaderProps {
  state: BetState;
  gameNumber: number;
  progress: number;
}
interface BetBlockProps {
  state?: BetState;
  gameNumber?: number;
  currentPrice?: number;
  lockedPrice?: number;
  progress?: number;
  pool?: number;
}
const TEXT_MAP: { [key in BetState]: string } = {
  live: "LIVE",
  expired: "Expired",
  next: "Next",
  later: "Later",
};

const ICON_MAP: { [key in BetState]: React.ElementType } = {
  live: IoPlayCircleOutline,
  expired: CiNoWaitingSign,
  next: IoPlayCircleOutline,
  later: CiClock2,
};

const COLOR_MAP: { [key in BetState]: string } = {
  live: "bg-white",
  expired: "bg-gray-200",
  next: "bg-blue-600",
  later: "bg-gray-200",
};

const TEXT_FORMAT_MAP: { [key in BetState]: string } = {
  live: "text-blue-600",
  expired: "text-black",
  next: "text-white",
  later: "text-black",
};

const Header: React.FC<HeaderProps> = ({ state, gameNumber, progress }) => {
  const Icon = ICON_MAP[state];
  return (
    <div>
      <div
        className={clsx(
          "flex flex-row items-center pt-2 px-3",
          state === "live" ? "pb-1" : "pb-2",
          COLOR_MAP[state],
        )}
      >
        <Icon className={clsx("mr-2 text-xl", TEXT_FORMAT_MAP[state])} />
        <h2 className={clsx("flex-1", TEXT_FORMAT_MAP[state])}>
          {TEXT_MAP[state]}
        </h2>
        <h3 className={TEXT_FORMAT_MAP[state]}>#{gameNumber}</h3>
      </div>
      <div
        className="w-full bg-gray-200 h-1 dark:bg-gray-700"
        style={{ opacity: state === "live" ? 1 : 0 }}
      >
        <div
          className="bg-blue-600 h-1"
          style={{ width: `${100 * progress}%` }}
        ></div>
      </div>
    </div>
  );
};

const BetBlock: React.FC<BetBlockProps> = ({
  state = "expired",
  gameNumber = 0,
  currentPrice = 509.7596,
  lockedPrice = 507.7262,
  pool = 0,
  progress = 0.5,
}) => {
  const priceDelta = lockedPrice - currentPrice;

  return (
    <div
      className={`w-80 h-96 bg-white rounded-3xl mb-4 overflow-hidden mr-4 flex flex-col ${
        state === "expired"
          ? "opacity-50 hover:opacity-100 transition-opacity"
          : ""
      }`}
    >
      <Header state={state} gameNumber={gameNumber} progress={progress} />
      <div className="flex justify-center flex-grow">
        {state === "next" && <NextState pool={pool} />}
        {state === "later" && <LaterState />}
        {state === "live" && (
          <LiveState currentPrice={currentPrice} priceDelta={priceDelta} />
        )}
        {state === "expired" && (
          <ExpiredState currentPrice={currentPrice} priceDelta={priceDelta} />
        )}
      </div>
    </div>
  );
};

const NextState: React.FC<{ pool: number }> = ({ pool }) => {
  const [betState, setBetState] = useState<'initial' | 'up' | 'down'>('initial');
  const [betAmount, setBetAmount] = useState<string>('');

  const handleBetUp = () => {
    setBetState('up');
  };

  const handleBetDown = () => {
    setBetState('down');
  };

  const handleSubmit = () => {
    console.log(`Bet ${betState} submitted with amount: ${betAmount}`);
    // Add your logic here
    setBetState('initial');
    setBetAmount('');
  };

  return (
    <div className="flex flex-col items-center justify-center w-full h-full p-8">
      <div className="flex flex-row w-full mb-2">
        <h2 className="flex-1">Prize Pool:</h2>
        <h3>{pool}</h3>
      </div>
      {betState === 'initial' ? (
        <div className="flex flex-row w-full">
          <button
            className="flex-1 bg-green-500 text-white px-4 py-2 rounded-lg mr-4 active:bg-green-600"
            onClick={handleBetUp}
          >
            Bet Up
          </button>
          <button
            className="flex-1 bg-red-500 text-white px-4 py-2 rounded-lg active:bg-red-600"
            onClick={handleBetDown}
          >
            Bet Down
          </button>
        </div>
      ) : (
        <div className="flex flex-col w-full">
          <input
            type="number"
            value={betAmount}
            onChange={(e) => setBetAmount(e.target.value)}
            className="w-full px-4 py-2 mb-2 border rounded-lg"
            placeholder="Enter bet amount"
          />
          <button
            className={`w-full text-white px-4 py-2 rounded-lg ${
              betState === 'up' ? 'bg-green-500 active:bg-green-600' : 'bg-red-500 active:bg-red-600'
            }`}
            onClick={handleSubmit}
          >
            Submit {betState === 'up' ? 'Up' : 'Down'} Bet
          </button>
        </div>
      )}
    </div>
  );
};

const LaterState: React.FC = () => (
  <div className="flex flex-col items-center justify-center w-full h-full">
    <h3>Entry Starts</h3>
    <h3>~0:00</h3>
  </div>
);

const LiveState: React.FC<{ currentPrice: number; priceDelta: number }> = ({
  currentPrice,
  priceDelta,
}) => (
  <div className="flex flex-col items-center justify-center w-full h-full">
    <div className="w-full h-full px-8 py-16">
      <div className="flex flex-col w-full h-full border-green-400 border rounded-3xl p-4">
        <h2>LAST PRICE</h2>
        <PriceDisplay currentPrice={currentPrice} priceDelta={priceDelta} />
      </div>
    </div>
  </div>
);

const ExpiredState: React.FC<{ currentPrice: number; priceDelta: number }> = ({
  currentPrice,
  priceDelta,
}) => (
  <div className="flex flex-col items-center justify-center w-full h-full">
    <div className="w-full h-full px-8 py-16">
      <div className="flex flex-col w-full h-full border-green-400 border rounded-3xl p-4">
        <h2>CLOSED PRICE</h2>
        <PriceDisplay currentPrice={currentPrice} priceDelta={priceDelta} />
      </div>
    </div>
  </div>
);

const PriceDisplay: React.FC<{ currentPrice: number; priceDelta: number }> = ({
  currentPrice,
  priceDelta,
}) => (
  <div className="flex flex-row items-center">
    <h3 className="flex-1">${currentPrice.toFixed(4)}</h3>
    <div
      className={clsx(
        "flex flex-row items-center text-white rounded-lg p-1",
        priceDelta > 0
          ? "bg-green-500"
          : priceDelta < 0
          ? "bg-red-500"
          : "bg-gray-500"
      )}
    >
      {priceDelta > 0 ? (
        <IoIosArrowUp className="mr-1" />
      ) : priceDelta < 0 ? (
        <IoIosArrowDown className="mr-1" />
      ) : (
        <PiEquals className="mr-1" />
      )}
      <h3 className="text-white">${Math.abs(priceDelta).toFixed(4)}</h3>
    </div>
  </div>
);

export default BetBlock;
