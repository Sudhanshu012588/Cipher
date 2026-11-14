import './App.css'
import { BrowserRouter, Routes, Route } from "react-router-dom"
import Home from "./Pages/Home.tsx"
import ColumnDesign from './Pages/ColumnDesign.tsx'
import BeamDesign from './Pages/BeamDesign.tsx'
function App() {
  return (
    <>
      <BrowserRouter>
        <Routes>
          <Route path='/' element={<Home/>}/>
          <Route path='/column' element={<ColumnDesign/>}/>
          <Route path='/beam' element={<BeamDesign/>}/>
        </Routes>
      </BrowserRouter>
    </>
  )
}

export default App
