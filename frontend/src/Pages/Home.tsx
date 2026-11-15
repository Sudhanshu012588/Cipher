import { ArrowRight, Box, Columns3 } from "lucide-react";
import { useNavigate } from "react-router";
import Navbar from "../Components/Navbar.tsx";

const designs = [
  {
    icon: <Box size={28} />,
    title: "Beam",
    description: "Design, verify, visualize, and report structural steel beams.",
    path: "/beam",
  },
  {
    icon: <Columns3 size={28} />,
    title: "Column",
    description: "Design, verify, visualize, and report structural steel columns.",
    path: "/column",
  },
];

const Home = () => (
  <div className="min-h-screen bg-slate-100 text-slate-800">
    <Navbar />
    <main className="max-w-5xl mx-auto px-6 py-12">
      <section className="mb-10">
        <p className="text-orange-600 text-xs font-bold tracking-[0.2em]">
          STRUCTURAL DESIGN
        </p>
        <h1 className="mt-2 text-3xl font-semibold text-slate-900">
          Design Workspace
        </h1>
        <p className="mt-2 text-sm text-slate-500">
          Choose a supported backend design workflow to begin.
        </p>
      </section>

      <section className="grid grid-cols-1 sm:grid-cols-2 gap-5">
        {designs.map((design) => (
          <DesignCard key={design.path} {...design} />
        ))}
      </section>
    </main>
  </div>
);

type DesignCardProps = (typeof designs)[number];

const DesignCard = ({ icon, title, description, path }: DesignCardProps) => {
  const navigate = useNavigate();

  return (
    <button
      type="button"
      onClick={() => navigate(path)}
      className="group text-left bg-white border border-slate-200 rounded-lg p-6 cursor-pointer transition-all duration-200 hover:border-orange-400 hover:shadow-md"
    >
      <div className="h-12 w-12 rounded-lg bg-slate-100 text-slate-700 flex items-center justify-center group-hover:bg-orange-50 group-hover:text-orange-600 transition">
        {icon}
      </div>
      <h2 className="mt-5 text-base font-semibold text-slate-900">{title}</h2>
      <p className="mt-2 text-xs leading-5 text-slate-500">{description}</p>
      <div className="mt-6 flex items-center gap-2 text-xs font-medium text-orange-600">
        Start Design
        <ArrowRight
          size={14}
          className="transition-transform group-hover:translate-x-1"
        />
      </div>
    </button>
  );
};

export default Home;
