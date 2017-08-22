import showModal from 'discourse/lib/show-modal';

export default {
  actions: {
    createElection(categoryId) {
      showModal('create-election', { model: { categoryId }});
    }
  }
}
