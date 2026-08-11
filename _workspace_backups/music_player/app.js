// Music Player Data
const tracks = [
    {
        id: '1',
        title: 'Cyber Soul',
        artist: 'Quantum',
        art: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300&h=300&fit=crop',
        duration: '3:45'
    },
    {
        id: '2',
        title: 'Midnight Rain',
        artist: 'Lofi Girl',
        art: 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?w=300&h=300&fit=crop',
        duration: '2:58'
    },
    {
        id: '3',
        title: 'Neon Pulse',
        artist: 'Synthwave',
        art: 'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?w=300&h=300&fit=crop',
        duration: '4:12'
    },
    {
        id: '4',
        title: 'Golden Hour',
        artist: 'Acoustic Vibes',
        art: 'https://images.unsplash.com/photo-1459749411177-042180ce673c?w=300&h=300&fit=crop',
        duration: '3:20'
    },
    {
        id: '5',
        title: 'Electric Sky',
        artist: 'Aura',
        art: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=300&h=300&fit=crop',
        duration: '5:05'
    },
    {
        id: '6',
        title: 'Deep Ocean',
        artist: 'Zen Master',
        art: 'https://images.unsplash.com/photo-1514525253361-b83f8a9e2769?w=300&h=300&fit=crop',
        duration: '7:30'
    }
];

const genres = [
    { name: 'Electronic', color: '#7c3aed' },
    { name: 'Lo-Fi', color: '#ec4899' },
    { name: 'Acoustic', color: '#f59e0b' },
    { name: 'Jazz', color: '#10b981' },
    { name: 'Classical', color: '#3b82f6' },
    { name: 'Synthwave', color: '#f43f5e' }
];

// State Management
let currentTrackIndex = -1;
let isPlaying = false;
let playlists = JSON.parse(localStorage.getItem('musicstream_playlists')) || [
    { id: 'p1', name: 'Chill Beats', tracks: ['1', '2'] },
    { id: 'p2', name: 'Workout Power', tracks: ['3', '5'] }
];

// DOM Elements
const pages = document.querySelectorAll('.page');
const navItems = document.querySelectorAll('.nav-item');
const playerTrackArt = document.getElementById('playerTrackArt');
const playerTrackTitle = document.getElementById('playerTrackTitle');
const playerTrackArtist = document.getElementById('playerTrackArtist');
const globalPlayBtn = document.getElementById('globalPlayBtn');
const progressFill = document.getElementById('progressFill');
const currentTimeEl = document.getElementById('currentTime');
const totalTimeEl = document.getElementById('totalTime');
const sidebarPlaylists = document.getElementById('sidebarPlaylists');
const playlistContainer = document.getElementById('playlistContainer');

// Initialization
function init() {
    renderGrid('recommendedGrid', tracks.slice(0, 4));
    renderGrid('trendingGrid', tracks.slice(2, 6));
    renderGenres();
    renderSidebarPlaylists();
    renderLibraryPlaylists();
    setupNavigation();
    setupPlayer();
    
    // Create Playlist functionality
    document.getElementById('createPlaylistBtn').addEventListener('click', createNewPlaylist);
}

// UI Rendering
function renderGrid(elementId, items) {
    const grid = document.getElementById(elementId);
    if (!grid) return;
    
    grid.innerHTML = items.map(track => `
        <div class="card" onclick="playTrackById('${track.id}')">
            <img src="${track.art}" alt="${track.title}" class="card-image">
            <div class="card-play"><i class="fas fa-play"></i></div>
            <h3>${track.title}</h3>
            <p>${track.artist}</p>
        </div>
    `).join('');
}

function renderGenres() {
    const grid = document.getElementById('genreGrid');
    if (!grid) return;
    
    grid.innerHTML = genres.map(genre => `
        <div class="card" style="background: ${genre.color}33; border-color: ${genre.color}66;">
            <div style="height: 140px; display: flex; align-items: center; justify-content: center; font-size: 3rem; opacity: 0.2">
                <i class="fas fa-music"></i>
            </div>
            <h3 style="margin-top: 12px">${genre.name}</h3>
        </div>
    `).join('');
}

function renderSidebarPlaylists() {
    sidebarPlaylists.innerHTML = playlists.map(p => `
        <li onclick="switchPage('library')">${p.name}</li>
    `).join('');
}

function renderLibraryPlaylists() {
    if (!playlistContainer) return;
    
    playlistContainer.innerHTML = playlists.map(p => `
        <div class="card" style="display: flex; flex-direction: row; align-items: center; gap: 20px; width: 100%; margin-bottom: 12px; padding: 16px;">
            <div style="width: 60px; height: 60px; background: var(--primary); border-radius: 12px; display: flex; align-items: center; justify-content: center; font-size: 1.5rem;">
                <i class="fas fa-list"></i>
            </div>
            <div style="flex: 1">
                <h3 style="margin: 0">${p.name}</h3>
                <p style="margin: 0">${p.tracks.length} tracks</p>
            </div>
            <button class="btn-icon delete-playlist" data-id="${p.id}"><i class="fas fa-trash"></i></button>
        </div>
    `).join('');
    
    // Add delete listeners
    document.querySelectorAll('.delete-playlist').forEach(btn => {
        btn.onclick = (e) => {
            e.stopPropagation();
            deletePlaylist(btn.dataset.id);
        };
    });
}

// Navigation Logic
function setupNavigation() {
    navItems.forEach(item => {
        item.addEventListener('click', () => {
            const pageId = item.getAttribute('data-page');
            switchPage(pageId);
        });
    });
}

window.switchPage = function(pageId) {
    pages.forEach(p => p.classList.remove('active'));
    navItems.forEach(n => n.classList.remove('active'));
    
    document.getElementById(pageId).classList.add('active');
    document.querySelector(`[data-page="${pageId}"]`).classList.add('active');
    
    // Scroll to top
    document.querySelector('.main-view').scrollTop = 0;
};

// Player Logic
function setupPlayer() {
    globalPlayBtn.addEventListener('click', togglePlay);
    document.getElementById('nextTrackBtn').addEventListener('click', playNext);
    document.getElementById('prevTrackBtn').addEventListener('click', playPrev);
    
    // Volume Simulation
    const volumeBar = document.getElementById('volumeBar');
    const volumeFill = document.getElementById('volumeFill');
    volumeBar.addEventListener('click', (e) => {
        const rect = volumeBar.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        volumeFill.style.width = (percent * 100) + '%';
    });
    
    // Progress Bar Simulation
    const progressBar = document.getElementById('progressBar');
    progressBar.addEventListener('click', (e) => {
        if (currentTrackIndex === -1) return;
        const rect = progressBar.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        progressFill.style.width = (percent * 100) + '%';
    });
}

window.playTrackById = function(id) {
    const index = tracks.findIndex(t => t.id === id);
    if (index !== -1) {
        currentTrackIndex = index;
        loadTrack(tracks[index]);
        if (!isPlaying) togglePlay();
    }
};

function loadTrack(track) {
    playerTrackArt.src = track.art;
    playerTrackTitle.innerText = track.title;
    playerTrackArtist.innerText = track.artist;
    totalTimeEl.innerText = track.duration;
    progressFill.style.width = '0%';
    currentTimeEl.innerText = '0:00';
}

function togglePlay() {
    if (currentTrackIndex === -1) {
        currentTrackIndex = 0;
        loadTrack(tracks[0]);
    }
    
    isPlaying = !isPlaying;
    globalPlayBtn.innerHTML = isPlaying ? '<i class="fas fa-pause"></i>' : '<i class="fas fa-play"></i>';
    
    if (isPlaying) {
        startProgress();
    } else {
        stopProgress();
    }
}

let progressInterval;
function startProgress() {
    progressInterval = setInterval(() => {
        const currentWidth = parseFloat(progressFill.style.width) || 0;
        if (currentWidth < 100) {
            progressFill.style.width = (currentWidth + 0.5) + '%';
            updateTimer(currentWidth + 0.5);
        } else {
            playNext();
        }
    }, 500);
}

function stopProgress() {
    clearInterval(progressInterval);
}

function updateTimer(percent) {
    const track = tracks[currentTrackIndex];
    const [min, sec] = track.duration.split(':').map(Number);
    const totalSec = min * 60 + sec;
    const currentTotalSec = Math.floor((percent / 100) * totalSec);
    
    const m = Math.floor(currentTotalSec / 60);
    const s = Math.floor(currentTotalSec % 60);
    currentTimeEl.innerText = `${m}:${s.toString().padStart(2, '0')}`;
}

function playNext() {
    currentTrackIndex = (currentTrackIndex + 1) % tracks.length;
    loadTrack(tracks[currentTrackIndex]);
    if (!isPlaying) isPlaying = true;
    globalPlayBtn.innerHTML = '<i class="fas fa-pause"></i>';
}

function playPrev() {
    currentTrackIndex = (currentTrackIndex - 1 + tracks.length) % tracks.length;
    loadTrack(tracks[currentTrackIndex]);
    if (!isPlaying) isPlaying = true;
    globalPlayBtn.innerHTML = '<i class="fas fa-pause"></i>';
}

// Playlist Management
function createNewPlaylist() {
    const name = prompt('Enter playlist name:');
    if (name) {
        const newPlaylist = {
            id: 'p' + Date.now(),
            name: name,
            tracks: []
        };
        playlists.push(newPlaylist);
        savePlaylists();
        renderSidebarPlaylists();
        renderLibraryPlaylists();
    }
}

function deletePlaylist(id) {
    playlists = playlists.filter(p => p.id !== id);
    savePlaylists();
    renderSidebarPlaylists();
    renderLibraryPlaylists();
}

function savePlaylists() {
    localStorage.setItem('musicstream_playlists', JSON.stringify(playlists));
}

// Kick off
init();
