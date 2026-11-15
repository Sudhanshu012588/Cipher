import { Link } from "react-router";
const Navbar = () => {
  return (
    <header className="h-[68px] bg-[#111a24] text-white border-b border-slate-700">
      <div className="h-full px-8 flex items-center">

        {/* Logo */}
        <Link to="/" className="flex items-center gap-3 min-w-[260px]">

          <div className="h-9 w-9 rounded-md bg-orange-600 flex items-center justify-center font-bold text-lg">
            S
          </div>

          <div>
            <h1 className="text-sm font-bold tracking-[0.18em]">
              CIPHER
            </h1>

            <p className="text-[9px] text-slate-400 tracking-wide">
              STRUCTURAL DESIGN
            </p>
          </div>

        </Link>


        {/* Navigation */}
        <nav className="hidden md:flex items-center h-full">

          <Link
            to="/"
            className="h-full px-5 flex items-center text-sm text-white border-b-2 border-orange-500"
          >
            Home
          </Link>

          <Link
            to="/column"
            className="h-full px-5 flex items-center text-sm text-slate-400 hover:text-white transition"
          >
            Column
          </Link>

          <Link
            to="/beam"
            className="h-full px-5 flex items-center text-sm text-slate-400 hover:text-white transition"
          >
            Beam
          </Link>

        </nav>


      </div>
    </header>
  );
};

export default Navbar;