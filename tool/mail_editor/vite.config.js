import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    cssCodeSplit: false,
    emptyOutDir: false,
    lib: {
      entry: 'src/editor.ts',
      formats: ['iife'],
      name: 'BnbuMailEditor',
      fileName: () => 'editor.js',
    },
    minify: false,
    outDir: '../../assets/mail_editor',
  },
});
