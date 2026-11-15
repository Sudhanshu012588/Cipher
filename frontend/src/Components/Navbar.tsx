import { Link } from "react-router";
import { Settings } from "lucide-react";

const Navbar = () => {
  return (
    <header className="h-17 bg-[#111a24] text-white border-b border-slate-700">
      <div className="h-full px-8 flex items-center">

        {/* Logo */}
        <Link to="/" className="flex items-center gap-3 min-w-65">

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
            to="/projects"
            className="h-full px-5 flex items-center text-sm text-slate-400 hover:text-white transition"
          >
            Projects
          </Link>

          <Link
            to="/design"
            className="h-full px-5 flex items-center text-sm text-slate-400 hover:text-white transition"
          >
            Design
          </Link>

          <Link
            to="/reports"
            className="h-full px-5 flex items-center text-sm text-slate-400 hover:text-white transition"
          >
            Reports
          </Link>

        </nav>


        {/* Right side */}
        <div className="ml-auto flex items-center gap-5">

          <button className="text-slate-400 hover:text-white transition">
            <Settings size={18} />
          </button>

          <div className="h-8 w-8 rounded-full bg-slate-700 flex items-center justify-center text-xs font-semibold">
            SJ
          </div>

        </div>

      </div>
    </header>
  );
};

export default Navbar;