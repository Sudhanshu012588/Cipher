import {
  ArrowRight,
  Box,
  Columns3,
  GitBranch,
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

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">

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
  icon={<GitBranch size={28} />}
  title="Splicing"
  description="Design structural member splice connections."
  path="/splicing"
/>

<DesignCard
  icon={<Layers3 size={28} />}
  title="Batten Column"
  description="Design built-up columns with batten connections."
  path="/batten-column"
/>

          </div>

        </section>


        {/* Recent Designs */}
        <section className="mt-12">

          <div className="flex items-center justify-between mb-4">

            <div>
              <h2 className="text-lg font-semibold text-slate-900">
                Recent Designs
              </h2>

              <p className="text-xs text-slate-500 mt-1">
                Continue working on your previous designs.
              </p>
            </div>

            <button className="text-xs text-orange-600 hover:text-orange-700">
              View all
            </button>

          </div>


          <div className="bg-white border border-slate-200 rounded-lg overflow-hidden">

            <RecentDesign
              type="BEAM"
              name="Main Floor Beam"
              date="26 Aug 2026"
            />

            <RecentDesign
              type="COLUMN"
              name="Ground Floor Column"
              date="25 Aug 2026"
            />

            <RecentDesign
              type="SPLICING"
              name="Steel Beam Splice"
              date="24 Aug 2026"
            />

          </div>

        </section>

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
      className="group bg-white border border-slate-200 rounded-lg p-6 cursor-pointer transition-all duration-200 hover:border-orange-400 hover:shadow-md"
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


/* ================= RECENT DESIGN ================= */

type RecentDesignProps = {
  type: string;
  name: string;
  date: string;
};

const RecentDesign = ({
  type,
  name,
  date,
}: RecentDesignProps) => {

  return (
    <div className="flex items-center px-5 py-4 border-b border-slate-100 last:border-b-0 hover:bg-slate-50 transition">

      {/* Type */}
      <div className="w-24">

        <span className="text-[9px] font-bold tracking-wide px-2 py-1 rounded bg-slate-100 text-slate-600">
          {type}
        </span>

      </div>


      {/* Name */}
      <div className="flex-1">

        <p className="text-sm font-medium text-slate-800">
          {name}
        </p>

      </div>


      {/* Date */}
      <div className="text-xs text-slate-400">
        {date}
      </div>


      <ArrowRight
        size={15}
        className="ml-5 text-slate-400"
      />

    </div>
  );
};


export default Home;