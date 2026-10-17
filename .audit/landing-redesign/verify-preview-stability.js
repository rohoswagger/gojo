(async () => {
  const buttons = [...document.querySelectorAll('[aria-label="Explore Gojo\'s tools"] button')];
  if (buttons.length !== 4) throw new Error('Expected four product views');
  const results = [];
  for (const button of buttons) {
    button.click();
    await new Promise(resolve => setTimeout(resolve, 75));
    results.push({
      view: button.textContent,
      frameHeight: document.querySelector('#product-view').getBoundingClientRect().height,
      heroHeight: document.querySelector('main section').getBoundingClientRect().height,
      galleryTop: document.querySelector('#features').getBoundingClientRect().top,
    });
  }
  for (const field of ['frameHeight', 'heroHeight', 'galleryTop']) {
    const values = results.map(result => result[field]);
    if (Math.max(...values) - Math.min(...values) > 0.5) throw new Error(`${field} changes when selecting a view`);
  }
  return { stable: true, results };
})()
