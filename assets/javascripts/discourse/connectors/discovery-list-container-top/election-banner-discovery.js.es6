export default {
  setupComponent(attrs, component) {
    component.set('electionListEnabled', Discourse.SiteSettings.elections_status_banner_discovery);
  }
};
