
import {
  ArrowRight,
  Box,
  Columns3,
  Layers3,
} from "lucide-react";

import { useNavigate } from "react-router";
import Navbar from "../Components/Navbar.tsx";
const Home = () => {
  return (
    <div className="min-h-screen bg-slate-100 text-slate-800">

      <Navbar />

      <main className="max-w-7xl mx-auto px-6 py-12">

        {/* Header */}
        <section className="mb-10">

          <p className="text-orange-600 text-xs font-bold tracking-[0.2em]">
            STRUCTURAL DESIGN
          </p>

          <h1 className="mt-2 text-3xl font-semibold text-slate-900">
            Design Workspace
          </h1>

          <p className="mt-2 text-sm text-slate-500">
            Select a structural member to begin your design.
          </p>

        </section>


        {/* Design Cards */}
        <section>

          <div className="flex flex-col">

            {/* Beam */}
            <DesignCard
  icon={<Box size={28} />}
  title="Beam"
  description="Design reinforced concrete and steel beams."
  path="/beam"
/>

<DesignCard
  icon={<Columns3 size={28} />}
  title="Column"
  description="Design structural columns for axial and bending loads."
  path="/column"
/>

<DesignCard
  icon={<Layers3 size={28} />}
  title="Lacing"
  description="Design built-up columns with lacing connections."
  path="/lacing"
/>

          </div>

        </section>


        {/* Recent Designs */}
        

      </main>

    </div>
  );
};


/* ================= DESIGN CARD ================= */

type DesignCardProps = {
  icon: React.ReactNode;
  title: string;
  description: string;
  path: string;
};

const DesignCard = ({
  icon,
  title,
  description,
  path,
}: DesignCardProps) => {

  const navigate = useNavigate();

  return (
    <div
      onClick={() => navigate(path)}
      className=" mt-4 group bg-white border border-slate-200 rounded-lg p-6 cursor-pointer transition-all duration-200 hover:border-orange-400 hover:shadow-md"
    >

      {/* Icon */}
      <div className="h-12 w-12 rounded-lg bg-slate-100 text-slate-700 flex items-center justify-center group-hover:bg-orange-50 group-hover:text-orange-600 transition">
        {icon}
      </div>

      {/* Content */}
      <h2 className="mt-5 text-base font-semibold text-slate-900">
        {title}
      </h2>

      <p className="mt-2 text-xs leading-5 text-slate-500">
        {description}
      </p>

      {/* Action */}
      <div className="mt-6 flex items-center gap-2 text-xs font-medium text-orange-600">
        Start Design

        <ArrowRight
          size={14}
          className="transition-transform group-hover:translate-x-1"
        />
      </div>

    </div>
  );
};


export default Home;