export default {
  setupComponent(args, component) {
    component.set('showStatus', args.model.subtype === 'election');
  }
}
