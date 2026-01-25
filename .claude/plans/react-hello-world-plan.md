# Voyage Plan: React Hello World with Component Library

## Objective

Create a production-ready React application with TypeScript, a reusable component library documented in Storybook, and comprehensive documentation. The app should demonstrate best practices for React development including testing, linting, and type safety.

## Tasks

1. Initialize React project with Vite and TypeScript (no deps)
   - Run `npm create vite@latest . -- --template react-ts`
   - Configure tsconfig.json with strict mode
   - Files: package.json, tsconfig.json, vite.config.ts
   - Acceptance: `npm run dev` starts dev server successfully

2. Configure ESLint and Prettier (no deps)
   - Install eslint, prettier, and React-specific plugins
   - Create .eslintrc.cjs and .prettierrc configs
   - Add lint scripts to package.json
   - Files: .eslintrc.cjs, .prettierrc, package.json
   - Acceptance: `npm run lint` runs without errors

3. Set up Vitest for testing (depends: 1)
   - Install vitest, @testing-library/react, jsdom
   - Configure vitest.config.ts
   - Add test scripts to package.json
   - Files: vitest.config.ts, package.json, src/setupTests.ts
   - Acceptance: `npm test` runs successfully

4. Install and configure Storybook (depends: 1)
   - Run `npx storybook@latest init`
   - Configure for Vite and TypeScript
   - Files: .storybook/main.ts, .storybook/preview.ts
   - Acceptance: `npm run storybook` launches Storybook UI

5. Create Button component (depends: 1, 2)
   - Create reusable Button with variants (primary, secondary, outline)
   - Include size props (sm, md, lg)
   - Add proper TypeScript types
   - Files: src/components/Button/Button.tsx, src/components/Button/Button.module.css, src/components/Button/index.ts
   - Acceptance: Button renders with all variant/size combinations

6. Write Button component tests (depends: 3, 5)
   - Test all variants render correctly
   - Test click handlers work
   - Test accessibility (button role)
   - Files: src/components/Button/Button.test.tsx
   - Acceptance: All Button tests pass

7. Create Button Storybook stories (depends: 4, 5)
   - Create stories for all variants and sizes
   - Add controls for interactive props
   - Include documentation in MDX
   - Files: src/components/Button/Button.stories.tsx, src/components/Button/Button.mdx
   - Acceptance: Button appears in Storybook with working controls

8. Create Card component (depends: 1, 2)
   - Create Card with header, body, footer slots
   - Support variant styles (elevated, outlined)
   - Files: src/components/Card/Card.tsx, src/components/Card/Card.module.css, src/components/Card/index.ts
   - Acceptance: Card renders with all slot combinations

9. Write Card component tests (depends: 3, 8)
   - Test slot rendering
   - Test variant styles apply
   - Files: src/components/Card/Card.test.tsx
   - Acceptance: All Card tests pass

10. Create Card Storybook stories (depends: 4, 8)
    - Create stories showing slot usage
    - Document props with controls
    - Files: src/components/Card/Card.stories.tsx
    - Acceptance: Card appears in Storybook with examples

11. Create Input component (depends: 1, 2)
    - Create controlled Input with label
    - Support error state and helper text
    - Files: src/components/Input/Input.tsx, src/components/Input/Input.module.css, src/components/Input/index.ts
    - Acceptance: Input handles controlled value changes

12. Write Input component tests (depends: 3, 11)
    - Test value changes
    - Test error state rendering
    - Test label association (accessibility)
    - Files: src/components/Input/Input.test.tsx
    - Acceptance: All Input tests pass

13. Create Input Storybook stories (depends: 4, 11)
    - Show default, error, and disabled states
    - Document accessibility considerations
    - Files: src/components/Input/Input.stories.tsx
    - Acceptance: Input appears in Storybook

14. Create component library index (depends: 5, 8, 11)
    - Create barrel exports for all components
    - Set up proper module structure
    - Files: src/components/index.ts
    - Acceptance: `import { Button, Card, Input } from './components'` works

15. Build Hello World App page (depends: 14)
    - Create main App using Button, Card, Input components
    - Demonstrate component library usage
    - Files: src/App.tsx, src/App.module.css
    - Acceptance: App displays "Hello World" with styled components

16. Write App integration tests (depends: 3, 15)
    - Test App renders without errors
    - Test component interactions work together
    - Files: src/App.test.tsx
    - Acceptance: App tests pass

17. Create README documentation (depends: 15)
    - Document project setup and installation
    - Explain component library usage
    - Include development workflow
    - Files: README.md
    - Acceptance: README has setup, usage, and contribution sections

18. Create component library documentation (depends: 14, 17)
    - Document each component's API
    - Include usage examples
    - Files: docs/COMPONENTS.md
    - Acceptance: All components have documented props and examples

19. Configure CI-ready scripts (depends: 2, 3)
    - Add typecheck script
    - Ensure all scripts return proper exit codes
    - Files: package.json
    - Acceptance: `npm run lint && npm run typecheck && npm test && npm run build` all pass

20. Verify exit criteria (depends: ALL)
    - Run ~/voyage/artifacts/verify.sh and ensure all commands pass
    - Fix any failing checks
    - Files: none (verification only)
    - Acceptance: All exit criteria commands return 0

## Exit Criteria

```bash
npm run lint
npm run typecheck
npm test -- --run
npm run build
```

## Requirements

- [ ] React app runs with `npm run dev`
- [ ] TypeScript strict mode enabled
- [ ] ESLint and Prettier configured
- [ ] Vitest tests run and pass
- [ ] Storybook documents all components
- [ ] Button component with variants and sizes
- [ ] Card component with slots
- [ ] Input component with error states
- [ ] Components exported from single index
- [ ] README with setup instructions
- [ ] Component documentation complete
- [ ] All linting passes
- [ ] All tests pass
- [ ] Production build succeeds
