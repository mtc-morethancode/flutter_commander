// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

// https://astro.build/config
export default defineConfig({
	site: 'https://mtc-morethancode.github.io',
	base: '/flutter_commander',
	integrations: [
		starlight({
			title: 'flutter_commander',
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/mtc-morethancode/flutter_commander' },
			],
			sidebar: [
				{
					label: 'Getting Started',
					items: [
						{ label: 'Overview & Quickstart', slug: 'getting-started/quickstart' },
						{ label: 'Engineering Excellence (TDD & AI)', slug: 'getting-started/engineering-excellence' },
					],
				},
				{
					label: 'Core Architecture',
					items: [
						{ label: 'Architecture & Concepts', slug: 'core/architecture' },
						{ label: 'Declarative Concurrency', slug: 'core/concurrency' },
					],
				},
				{
					label: 'Features & Mixins',
					items: [
						{ label: 'Two-Tier Testing', slug: 'features/testing' },
						{ label: 'State Persistence', slug: 'features/saved-state' },
						{ label: 'Time-Travel & Undo/Redo', slug: 'features/undo-redo' },
						{ label: 'Observability & DevTools', slug: 'features/telemetry' },
					],
				},
				{
					label: 'Migration & Comparison',
					items: [
						{ label: 'Architectural Comparison', slug: 'migration/comparison' },
						{ label: 'Migrating from BLoC', slug: 'migration/from-bloc' },
						{ label: 'Migrating from Riverpod', slug: 'migration/from-riverpod' },
						{ label: 'Universal Migration Guide', slug: 'migration/universal-guide' },
					],
				},
			],
		}),
	],
});
