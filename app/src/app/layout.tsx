import '../styles/globals.css';

export const metadata = {
  title: 'Aptos Prediction Game',
  description: 'A prediction game on the Aptos blockchain',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className='bg-zinc-100'>
        {children}
      </body>
    </html>
  );
}

