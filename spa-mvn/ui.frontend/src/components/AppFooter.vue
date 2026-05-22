<script setup>
const columns = [
  {
    title: 'Product',
    links: ['Overview', 'Pricing', 'SPA Editor', 'Headless APIs', 'Personalization']
  },
  {
    title: 'Solutions',
    links: ['Enterprise', 'Mid-market', 'Public sector', 'Retail', 'Financial services']
  },
  {
    title: 'Resources',
    links: ['Documentation', 'API reference', 'Community', 'Status', 'Changelog']
  },
  {
    title: 'Company',
    links: ['About', 'Customers', 'Careers', 'Newsroom', 'Contact']
  }
]
const year = new Date().getFullYear()
</script>

<template>
  <footer class="ftr">
    <div class="container">
      <div class="ftr__top">
        <div class="ftr__brand">
          <div class="ftr__mark">SM</div>
          <p class="ftr__tagline">
            SPA Mountain is a modern composable content platform &mdash; built for the velocity teams expect today.
          </p>
        </div>

        <div class="ftr__cols">
          <div v-for="col in columns" :key="col.title" class="ftr__col">
            <h4 class="ftr__col-title">{{ col.title }}</h4>
            <ul class="ftr__col-list">
              <li v-for="l in col.links" :key="l"><a href="#">{{ l }}</a></li>
            </ul>
          </div>
        </div>
      </div>

      <div class="ftr__bottom">
        <small>&copy; {{ year }} SPA Mountain, a fictional demo. Built on AEM.</small>
        <div class="ftr__legal">
          <a href="#">Privacy</a>
          <a href="#">Terms</a>
          <a href="#">Cookies</a>
        </div>
      </div>
    </div>
  </footer>
</template>

<style scoped>
.ftr {
  background: #0a0a14;
  color: rgba(255, 255, 255, 0.78);
  padding: 72px 0 28px;
}
.ftr__top {
  display: grid;
  grid-template-columns: 1.2fr 3fr;
  gap: 56px;
  padding-bottom: 56px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
@media (max-width: 880px) { .ftr__top { grid-template-columns: 1fr; gap: 40px; } }

.ftr__brand { max-width: 360px; }
.ftr__mark {
  display: inline-grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: linear-gradient(135deg, #ff3b30, #1473e6);
  color: white;
  font-weight: 800;
  font-size: 14px;
  letter-spacing: 0.5px;
  margin-bottom: 18px;
}
.ftr__tagline { font-size: 14px; color: rgba(255, 255, 255, 0.6); margin: 0; line-height: 1.55; }

.ftr__cols {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 28px;
}
@media (max-width: 640px) { .ftr__cols { grid-template-columns: repeat(2, 1fr); } }

.ftr__col-title {
  font-size: 13px;
  font-weight: 700;
  color: white;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  margin: 0 0 16px;
}
.ftr__col-list { list-style: none; padding: 0; margin: 0; }
.ftr__col-list li { margin-bottom: 10px; }
.ftr__col-list a {
  font-size: 14px;
  color: rgba(255, 255, 255, 0.65);
  transition: color 0.15s ease;
}
.ftr__col-list a:hover { color: white; }

.ftr__bottom {
  display: flex;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 16px;
  padding-top: 28px;
  font-size: 13px;
  color: rgba(255, 255, 255, 0.5);
}
.ftr__legal { display: flex; gap: 18px; }
.ftr__legal a { color: rgba(255, 255, 255, 0.6); }
.ftr__legal a:hover { color: white; }
</style>
