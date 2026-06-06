import { defineConfig } from 'vite';

// แอป deploy ใต้ subpath ของ GitHub Pages: https://soonlearning09-lab.github.io/sp-classroom/
// จึงต้องตั้ง base ให้ตรง ไม่งั้น asset path จะผิด
export default defineConfig({
  base: '/sp-classroom/',
  build: {
    outDir: 'dist',
    target: 'es2018',
    sourcemap: false,
  },
});
